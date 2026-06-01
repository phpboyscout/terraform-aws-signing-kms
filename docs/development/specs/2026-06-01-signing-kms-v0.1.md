---
title: "signing-kms v0.1 — KMS asymmetric key + OIDC signer role"
description: "First release of terraform-aws-signing-kms: an asymmetric AWS KMS key (default RSA-4096 SIGN_VERIFY) plus an IAM role assumable from an external OIDC IDP, scoped via caller-supplied StringLike sub patterns. Designed for release-binary signing chains where the apply role must not be able to mint signatures."
status: draft
date: 2026-06-01
authors: [Matt Cockayne]
tags: [spec, signing, kms, oidc, gitlab, module, v0.1]
---

# Spec: signing-kms v0.1

## Scope

A small, focused module that produces exactly two AWS resources plus
their policies:

1. An asymmetric KMS key (`SIGN_VERIFY`, default `RSA_4096`) with a
   stable alias.
2. An IAM role with an OIDC trust policy scoped to caller-supplied
   `StringLike` `sub` patterns, no attached IAM policy.

Plus the key policy that grants exactly four principal classes
(account root, administrators, automation, signer) the minimum
permissions each needs.

The consumer of v0.1 is `phpboyscout/infra` `src/main.signing-kms.tf`,
which feeds the role + key into `phpboyscout/go-tool-base`'s Phase 2
signed-update pipeline.

## Decisions

### D1 — Key spec defaults to `RSA_4096`

AWS KMS does not expose Ed25519 for asymmetric `SIGN_VERIFY` keys.
RSA-4096 is the strongest RSA option and matches the consuming repo's
prep-doc requirement. ECC variants are accepted via the
`key_spec` input but the default and recommended choice is RSA-4096
because the consumer's OpenPGP packet encoder is RSA-oriented.

### D2 — Signing algorithm chosen at sign time, not key creation

AWS KMS keys with `key_usage = SIGN_VERIFY` and `key_spec = RSA_4096`
support both `RSASSA_PSS_SHA_256` and `RSASSA_PKCS1_V1_5_SHA_256` at
sign time. The module does NOT add a `kms:SigningAlgorithm` condition
to the signer's key-policy statement, so the caller's signing shim can
pick whichever shape its envelope format expects:

- OpenPGP packet encoding traditionally uses PKCS#1 v1.5.
- Modern non-OpenPGP envelopes prefer PSS.

A future major version MAY add an `allowed_signing_algorithms` input
that materialises as a `StringEquals` condition; v0.1 leaves it open
for flexibility.

### D3 — Trust policy: caller passes the full `sub` patterns

The module accepts `ci_subject_filters` as a list of `StringLike`
patterns matched against `<issuer>:sub`. Validation enforces that:

- the list is non-empty (an empty list would trust every token from
  the issuer);
- each entry matches GitLab's OIDC `sub` shape
  `project_path:<group/repo>:ref_type:(branch|tag):ref:<pattern>`.

The validation is GitLab-specific because (a) GitLab is the only
issuer this module is built to support today, and (b) catching a
malformed pattern at plan time is much cheaper than catching it via a
failed `sts:AssumeRoleWithWebIdentity` at sign time.

The recommended scope is the tightest one: a single
`project_path:<consumer>:ref_type:tag:ref:v*` pattern. That trusts
exactly tag-pipelines whose tag matches the `v*` glob and rejects MR
+ branch pipelines (their `sub` contains `ref_type:branch`).

### D4 — Permission classes in the key policy

Four statements, four principal classes:

| Principal | Sid | Permitted |
|---|---|---|
| Account root | `EnableAccountRoot` | `kms:*` — break-glass |
| `var.key_administrator_arns` | `KeyAdministrators` | Lifecycle verbs (Create/Describe/Enable/List/Put/Update/Revoke/Disable/Get/Delete + Tag/Untag + Schedule/Cancel deletion). **Not** Sign, **not** PutKeyPolicy. |
| `var.automation_role_arn` | `AutomationManageKey` | DescribeKey, GetKeyPolicy, GetKeyRotationStatus, ListResourceTags, Tag/Untag, UpdateKeyDescription, PutKeyPolicy. Manages the key as a Terraform resource. **Not** Sign, **not** GetPublicKey. |
| Signer role | `SignerSign` | Sign, GetPublicKey, DescribeKey. **Nothing else.** |

The administrator class does NOT include `PutKeyPolicy` because policy
changes flow through Terraform — the automation role applies them. An
operator with the InfraAdmin role can change the policy by editing the
spec/module and going through the apply pipeline; direct console
edits are not part of the supported lifecycle.

### D5 — No attached IAM policy on the signer role

The role has no managed policy attached and no inline policy. The key
policy is sufficient for same-account access and is the single source
of permission grants. This:

- removes the audit risk of role-policy / key-policy drift;
- makes the role's effective permissions trivially auditable from a
  single document;
- prevents an attacker with `iam:PutRolePolicy` on the signer role
  (improbable but possible if IAM Access Analyzer findings are
  ignored) from quietly broadening access — the key policy still
  has the final say.

### D6 — Asymmetric `enable_key_rotation = false`

AWS KMS does not support managed rotation for asymmetric keys —
attempts return `UnsupportedOperationException`. Rotation is handled
out-of-band: mint a v2 instance of this module
(`name = "<consumer>-signing-v2"`), embed both v1 and v2 public keys
in the consumer's trust set during the support window, sign with both
(GoReleaser supports multiple `signs:` entries), then delete the v1
instance once the support window closes.

The `key_spec` and `name` inputs are intentionally immutable in
practice (any change forces destroy + recreate; never apply that on
a live signing key).

### D7 — `deletion_window_in_days = 30` default

The KMS-imposed maximum. For a signing key, the longest recovery
window is the safest default — accidental schedule-deletion gives 30
days of headroom to cancel before the key is unrecoverable. Callers
can shrink it for testing scenarios but the default favours safety.

### D8 — Tagging: `Component = "signing-kms"` + caller `var.tags`

Every taggable resource carries `merge(var.tags, { Component =
"signing-kms" })`. Cross-cutting tags (`Project`, `Environment`,
`ManagedBy`, `Repository`) come from the consuming stack's provider
`default_tags` block and must not be repeated here. This matches the
`terraform-aws-bootstrap` and `terraform-aws-security-baseline`
convention.

## Public interface

### Inputs

`name`, `description`, `key_spec`, `deletion_window_in_days`,
`oidc_provider_arn`, `oidc_audience`, `oidc_issuer_host`,
`ci_subject_filters`, `key_administrator_arns`, `automation_role_arn`,
`tags`. Every input has a `description` and a `type`; sensitive inputs
would be marked but none here are sensitive. Validations on `name`,
`key_spec`, `deletion_window_in_days`, `oidc_provider_arn`,
`oidc_issuer_host`, `ci_subject_filters`, `key_administrator_arns`,
`automation_role_arn` keep malformed input from reaching the apply
phase.

### Outputs

`key_id`, `key_arn`, `key_alias_name`, `key_alias_arn`,
`signer_role_arn`, `signer_role_name`. None are sensitive — the key
ARN and role ARN are not secrets (the secret is the assume-role
condition that scopes who can use them).

## Out of scope

- The OIDC IDP itself — `terraform-aws-bootstrap` owns it.
- The WKD endpoint — Cloudflare Pages, administered independently
  from AWS.
- Key rotation orchestration — out-of-band, by minting v2.
- The signing shim script — consumer-owned (`scripts/sign-release.sh`
  in the consumer's repo).
- Sigstore / Rekor integration — deferred to a future Phase per the
  consumer's spec.

## Open questions

| # | Question | Default if not answered |
|---|---|---|
| 1 | Should the module accept an `allowed_signing_algorithms` input that adds a `kms:SigningAlgorithm` condition to the signer statement? | Defer to v0.2 — keeping v0.1 minimal until a consumer needs the narrowing. |
| 2 | Should the role's `max_session_duration` be configurable? | Defer to v0.2 — 1h (`3600`) covers every release-job duration we have evidence for. |
| 3 | Should the module also create a corresponding `aws_iam_role_policy` for parity with conventional patterns, even though the key policy makes it redundant? | No — see D5. The redundancy is an explicit anti-goal. |
| 4 | Should the module emit a `CloudWatchLogs` log group for KMS use? | No — CloudTrail data events on the key are configured at the trail level (separate concern, in `terraform-aws-security-baseline`). |
