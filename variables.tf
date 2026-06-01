variable "name" {
  description = "Short kebab-case identifier for this signing key. Used to derive the IAM role name (`<name>-signer`) and the KMS alias (`alias/<name>`). Pick something descriptive that survives key rotation — e.g. `gtb-release-signing-v1` rather than `gtb-release-signing`."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,63}$", var.name))
    error_message = "name must be 2-64 chars, lowercase alphanumeric + hyphens, starting with a letter."
  }
}

variable "description" {
  description = "Human-readable description applied to the KMS key. Shown in the AWS console and in CloudTrail events; useful for auditors. Defaults to a generic string referencing the key's purpose."
  type        = string
  default     = "Release-binary signing key"
}

variable "key_spec" {
  description = "KMS asymmetric key spec. Must be a SIGN_VERIFY-capable spec. AWS KMS does not expose Ed25519 for asymmetric signing, so RSA_4096 is the secure default. ECC_NIST_P256 / P384 / P521 are accepted for callers that prefer EC signatures, but be aware OpenPGP packet encoding is tightly bound to the algorithm — RSA is the right choice for the go-tool-base / OpenPGP signing workflow this module was built for."
  type        = string
  default     = "RSA_4096"

  validation {
    condition = contains([
      "RSA_2048",
      "RSA_3072",
      "RSA_4096",
      "ECC_NIST_P256",
      "ECC_NIST_P384",
      "ECC_NIST_P521",
    ], var.key_spec)
    error_message = "key_spec must be one of the SIGN_VERIFY asymmetric specs supported by AWS KMS."
  }
}

variable "deletion_window_in_days" {
  description = "Number of days AWS KMS waits between schedule-deletion and actual deletion. Range 7-30. Defaults to the maximum (30) — for a signing key, the longest possible recovery window is the safest default."
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30 (AWS-imposed limits)."
  }
}

variable "oidc_provider_arn" {
  description = "ARN of the IAM OIDC identity provider whose tokens this role trusts. Typically the GitLab OIDC IDP provisioned by `terraform-aws-bootstrap` (output `oidc_provider_arn`). Pass via a `data.aws_iam_openid_connect_provider` lookup so the caller does not hardcode the ARN."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[^:]*:iam::[0-9]{12}:oidc-provider/.+$", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be an IAM OIDC provider ARN."
  }
}

variable "oidc_audience" {
  description = "OIDC `aud` claim value the token must carry. The downstream tool's `.gitlab-ci.yml` declares `id_tokens:` with this audience so the runner gets a token the role accepts. Defaults to `https://gitlab.com`, GitLab.com's well-known audience. Self-managed GitLab installs override this."
  type        = string
  default     = "https://gitlab.com"
}

variable "oidc_issuer_host" {
  description = "Hostname of the OIDC issuer, used as the prefix on the `aud` / `sub` condition keys (e.g. `gitlab.com:aud`). Defaults to `gitlab.com`. Override only for self-managed GitLab on a different host."
  type        = string
  default     = "gitlab.com"

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.oidc_issuer_host))
    error_message = "oidc_issuer_host must be a DNS hostname."
  }
}

variable "ci_subject_filters" {
  description = "List of GitLab OIDC `sub` claim patterns the role accepts. Wildcards (`*`) are matched with `StringLike`. The canonical scope for a release signer is one tag-pipeline pattern per consuming project, e.g. `project_path:phpboyscout/go-tool-base:ref_type:tag:ref:v*` — that allows tag pipelines for any `v*` ref and rejects MR/branch pipelines entirely. Must be non-empty."
  type        = list(string)

  validation {
    condition     = length(var.ci_subject_filters) > 0
    error_message = "ci_subject_filters must contain at least one pattern; an empty list would trust every token from the issuer."
  }

  validation {
    condition = alltrue([
      for s in var.ci_subject_filters : can(regex("^project_path:[a-z0-9_./-]+:ref_type:(branch|tag):ref:[^[:space:]]+$", s))
    ])
    error_message = "ci_subject_filters entries must match GitLab's OIDC `sub` format: project_path:<group/repo>:ref_type:(branch|tag):ref:<pattern>."
  }
}

variable "key_administrator_arns" {
  description = "Principal ARNs that may administer the key — schedule deletion, rotate policy, etc. Typically the operator role from `terraform-aws-security-baseline` plus the AWS account root. Used for break-glass; not used in normal operation. The signer role is intentionally NOT an administrator."
  type        = list(string)

  validation {
    condition     = length(var.key_administrator_arns) > 0
    error_message = "key_administrator_arns must contain at least one principal so the key remains administrable."
  }

  validation {
    condition = alltrue([
      for arn in var.key_administrator_arns : can(regex("^arn:aws[^:]*:iam::[0-9]{12}:(root|role/.+|user/.+)$", arn))
    ])
    error_message = "key_administrator_arns entries must be IAM root / role / user ARNs."
  }
}

variable "automation_role_arn" {
  description = "ARN of the IAM role the infra apply pipeline assumes. Granted the KMS permissions needed to *manage* the key resource via Terraform (Describe, Get, List, Tag, Put-policy, schedule deletion). Deliberately NOT granted `kms:Sign` — a compromise of the apply role must not let an attacker mint signatures."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[^:]*:iam::[0-9]{12}:role/.+$", var.automation_role_arn))
    error_message = "automation_role_arn must be an IAM role ARN."
  }
}

variable "tags" {
  description = "Tags to apply to every taggable resource. Merged with `Component = \"signing-kms\"` per the module-repo convention. Cross-cutting tags (Project, ManagedBy, Repository) come from the consuming stack's provider `default_tags`."
  type        = map(string)
  default     = {}
}
