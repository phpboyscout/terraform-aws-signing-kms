################################################################################
# terraform-aws-signing-kms
#
# Provisions:
#
#   1. An asymmetric AWS KMS key for release-binary signing (SIGN_VERIFY,
#      default RSA_4096) with a stable alias.
#   2. An IAM role assumable from an external OIDC IDP (default: GitLab.com),
#      with the role's trust policy scoped to a caller-supplied list of
#      OIDC `sub` patterns. The canonical scope is one tag-pipeline pattern
#      per consuming project, so only release-tag pipelines can mint signatures.
#
# The KMS key policy is the single source of permission grants for the key.
# Four distinct principal classes appear in the policy:
#
#   - account root             — `kms:*`, which also lets IAM policies in
#                                the account grant use of the key; bounded
#                                by the two Deny statements below
#   - key_administrator_arns   — an explicit list of lifecycle actions;
#                                not Sign, not PutKeyPolicy
#   - automation_role_arn      — manage the key via Terraform (read +
#                                tag + update-key-policy) but NOT Sign
#   - the signer role          — Sign + GetPublicKey + DescribeKey,
#                                nothing else
#
# Two Deny statements bound everything above, whatever any IAM policy says:
# only the signer role may Sign, and only the automation role may
# PutKeyPolicy. Recovery is therefore through the automation role; see
# "Break-glass" in the README.
#
# Deliberate omissions: the role has no attached IAM policy. The key
# policy is sufficient and avoids the audit risk of role-policy /
# key-policy drift. The role is single-purpose and only ever needs KMS
# Sign, so a separate IAM policy would be pure ceremony.
#
# See docs/development/specs/2026-06-01-signing-kms-v0.1.md for the design
# record.
################################################################################

locals {
  module_tags = merge(var.tags, {
    Component = "signing-kms"
  })

  alias_name      = "alias/${var.name}"
  signer_role_arn = aws_iam_role.signer.arn

  # Enumerated rather than wildcarded so the list states exactly what an
  # administrator can do. Sign, GetPublicKey and PutKeyPolicy are absent.
  key_administrator_actions = [
    "kms:DescribeKey",
    "kms:GetKeyPolicy",
    "kms:GetKeyRotationStatus",
    "kms:ListResourceTags",
    "kms:ListKeyPolicies",
    "kms:ListGrants",
    "kms:EnableKey",
    "kms:DisableKey",
    "kms:UpdateKeyDescription",
    "kms:CreateAlias",
    "kms:UpdateAlias",
    "kms:DeleteAlias",
    "kms:TagResource",
    "kms:UntagResource",
    "kms:RevokeGrant",
    "kms:ScheduleKeyDeletion",
    "kms:CancelKeyDeletion",
  ]
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ---- IAM role: assumable from the OIDC IDP, signs only -----------------------

resource "aws_iam_role" "signer" {
  name        = "${var.name}-signer"
  description = "Signer role for ${var.name} KMS key. Assumable via OIDC from the patterns in var.ci_subject_filters; permitted to call kms:Sign / kms:GetPublicKey on the key only."

  assume_role_policy   = data.aws_iam_policy_document.signer_assume.json
  max_session_duration = 3600

  tags = local.module_tags
}

data "aws_iam_policy_document" "signer_assume" {
  statement {
    sid     = "AssumeViaOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer_host}:aud"
      values   = [var.oidc_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${var.oidc_issuer_host}:sub"
      values   = var.ci_subject_filters
    }
  }
}

# ---- KMS key -----------------------------------------------------------------

resource "aws_kms_key" "this" {
  description              = var.description
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = var.key_spec
  deletion_window_in_days  = var.deletion_window_in_days

  # Asymmetric SIGN_VERIFY keys do not support KMS-managed rotation;
  # rotation is handled by minting a new key (alias = `<name>-v2`) and
  # publishing the v2 public key alongside the v1 key (dual-sign window),
  # per the consuming repo's signing-prep doc.
  enable_key_rotation = false

  policy = data.aws_iam_policy_document.key_policy.json

  tags = local.module_tags
}

resource "aws_kms_alias" "this" {
  name          = local.alias_name
  target_key_id = aws_kms_key.this.id
}

# ---- KMS key policy ----------------------------------------------------------

data "aws_iam_policy_document" "key_policy" {
  # checkov:skip=CKV_AWS_356:KMS key policy — `resources = "*"` is implicitly scoped to the single key the policy is attached to (key policies are not identity-based). Matches the pattern in terraform-aws-bootstrap/modules/state-backend.
  # checkov:skip=CKV_AWS_111:Same as CKV_AWS_356 — `*` in a KMS key policy resolves to this key only, not to write access on arbitrary resources.
  # checkov:skip=CKV_AWS_109:Same as CKV_AWS_356 — `*` is bounded by the attached key; this statement does not grant permissions-management on any other principal or resource.
  # The account root keeps `kms:*`, AWS's default, so the key cannot be
  # orphaned. That statement also delegates to IAM policies in the account,
  # which is why the DenySign and DenyPutKeyPolicy statements exist.
  statement {
    sid     = "EnableAccountRoot"
    effect  = "Allow"
    actions = ["kms:*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    resources = ["*"]
  }

  # Administrators manage the key's lifecycle. Signing is the signer
  # role's alone, and key-policy changes flow through the automation role's
  # reviewed plan/apply.
  statement {
    sid    = "KeyAdministrators"
    effect = "Allow"

    actions = local.key_administrator_actions

    principals {
      type        = "AWS"
      identifiers = var.key_administrator_arns
    }

    resources = ["*"]
  }

  # The infra-apply automation role can manage the key as a Terraform
  # resource: read metadata, update tags, push a new key policy. It
  # CANNOT Sign and it CANNOT GetPublicKey directly (it does not need to
  # — `data.aws_kms_key` only needs DescribeKey). A compromise of the
  # apply runner cannot mint signatures.
  statement {
    sid    = "AutomationManageKey"
    effect = "Allow"

    actions = [
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateKeyDescription",
      "kms:PutKeyPolicy",
    ]

    principals {
      type        = "AWS"
      identifiers = [var.automation_role_arn]
    }

    resources = ["*"]
  }

  # The signer role's only grant: Sign + GetPublicKey + DescribeKey.
  # DescribeKey is included because the AWS SDK Sign call requires the
  # caller to know the key's signing capabilities, which the SDK
  # resolves via a hidden DescribeKey when given an alias (vs. a key
  # ARN). Granting it does not leak any sensitive material — only
  # metadata that is otherwise published via the WKD-served public key.
  statement {
    sid    = "SignerSign"
    effect = "Allow"

    actions = [
      "kms:Sign",
      "kms:GetPublicKey",
      "kms:DescribeKey",
    ]

    principals {
      type        = "AWS"
      identifiers = [local.signer_role_arn]
    }

    resources = ["*"]
  }

  # The Denies match on aws:PrincipalArn rather than naming a principal, so
  # a role deleted and recreated under the same name and path is excepted
  # again. A Principal element would bind the deleted role's unique ID.
  statement {
    sid       = "DenySignExceptSigner"
    effect    = "Deny"
    actions   = ["kms:Sign"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [local.signer_role_arn]
    }
  }

  statement {
    sid       = "DenyPutKeyPolicyExceptAutomation"
    effect    = "Deny"
    actions   = ["kms:PutKeyPolicy"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [var.automation_role_arn]
    }
  }
}
