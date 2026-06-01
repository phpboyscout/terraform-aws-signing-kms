# examples/minimal

Validate-only fixture for `terraform-aws-signing-kms`. The placeholder
ARNs in `main.tf` match the module's input validations but do not
correspond to real AWS resources — running `tofu apply` against this
example would fail at the IAM trust-policy creation step.

CI runs `tofu init -backend=false && tofu validate` here to keep the
module's caller contract well-formed across changes.

To use the module in a real stack, see the parent README and the
[design spec](../../docs/development/specs/2026-06-01-signing-kms-v0.1.md).
