---
title: Engineering standards
description: Standing rules for module input/output discipline, tagging, security defaults, naming, and review.
status: active
date: 2026-04-26
authors: [Matt Cockayne]
---

# Engineering Standards

Standing rules for every contribution to this module. Deviations need a spec
entry justifying why.

## 1. Tagging — non-negotiable

**Every taggable resource accepts and propagates `var.tags`.** Two-layer
pattern:

1. **Provider-level `default_tags`** (set by the *caller*) — cross-cutting
   tags like `Project`, `ManagedBy`, `Repository`.
2. **Module-level `var.tags`** — exposed by every module, threaded through
   every taggable resource via `merge(var.tags, { … })` for any per-resource
   additions. Module-supplied tags win on key conflict.

When adding a new taggable resource: it MUST take
`tags = merge(var.tags, { Component = "<sub-module>" })` and the module's
`variables.tf` MUST expose a `tags` input. No exceptions.

### Standard tag set we expect callers to define

| Tag | Source | Required? |
|---|---|---|
| `Project` | provider `default_tags` | Yes |
| `Environment` | provider `default_tags` | Yes |
| `Stack` | provider `default_tags` | Yes |
| `ManagedBy` (always `opentofu`) | provider `default_tags` | Yes |
| `Repository` | provider `default_tags` | Yes |
| `Component` | per-resource via `merge()` | Per-module |
| `Owner` | provider `default_tags` (when CODEOWNERS isn't enough) | Recommended |
| `CostCenter` | provider `default_tags` | Recommended once billing is wired up |

### Multi-cloud anticipation

The sibling GCP module exposes `var.labels` (lower-case keys, alphanumeric
+ `-_`, max 63 chars on key and value). The sibling Azure module exposes
`var.tags` with Azure's stricter value validation (no `<>%&\?/`). Each
cloud's module is responsible for its own constraints.

## 2. Security defaults

- **No public-facing IAM trust by default.** OIDC trust policies pin
  `aws:RequestedRegion` (where applicable), the `sub` claim to the caller's
  repo + ref, and the audience to `sts.amazonaws.com`.
- **CMKs over AWS-managed keys.** State-bucket encryption uses a customer
  CMK with rotation, not `aws/s3`. Same for any KMS we provision.
- **TLS-only bucket policies.** State bucket and any other S3 we create
  refuses non-TLS access at the policy level.
- **`prevent_destroy` on irreversible resources.** State bucket, primarily.

## 3. Module input/output discipline

- Every `variable` has `type` and `description`. Sensitive inputs are
  `sensitive = true`.
- Every `output` has `description`. Sensitive outputs are `sensitive = true`.
- No provider configuration inside modules. The caller configures providers.
- No backend configuration inside modules. Modules don't manage their own
  state.
- Module sources for external dependencies are pinned (commit SHA or
  semver tag). `terraform_module_pinned_source` is enforced via tflint.

## 4. Naming

- Terraform locals: `snake_case`, singular.
- AWS resource `name` attributes: `kebab-case`, prefixed with the project
  tag (`pbs-<purpose>`). Caller can override via inputs.
- Variables: `snake_case`. Boolean variables start with `enable_` /
  `is_` / `has_`.
- Outputs: `snake_case`, describe the shape (`tfstate_bucket_arn`,
  not `arn`).

## 5. File organisation within a module

- `main.tf` — resource definitions.
- `variables.tf` — typed, described inputs.
- `outputs.tf` — described outputs.
- `versions.tf` — `required_version` + `required_providers`.
- `locals.tf` — shared locals (optional).
- `data.tf` — data sources (optional).
- `README.md` — usage example + auto-generated inputs/outputs table from
  terraform-docs.

Larger modules may split `main.tf` by concern (`main.policy.tf`, etc.).

## 6. Versioning

- Pre-1.0: minor bumps may break the input/output surface; document in the
  CHANGELOG with explicit `BREAKING CHANGE:` notes.
- Post-1.0: semver strictly.
- Tag releases as `v0.1.0`, `v0.1.1`, `v1.0.0`, etc.

## 7. Commit style

Conventional Commits. Scope is the sub-module short name:
`feat(state-backend):`, `fix(automation-iam):`, `chore(nuke-config):`. For
repo-wide changes use `module`. For CI/workflows use `ci`.

No AI attribution in commit messages.
