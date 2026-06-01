## Summary

<!-- One short paragraph describing the change. Cite the spec it implements. -->

## Test plan

- [ ] `just check` clean locally (`tofu fmt`, `tofu validate`, `tflint`, trivy, checkov).
- [ ] CI green: tofu-lint, tofu-security, tofu-validate.
- [ ] `terraform-docs` output committed (the drift gate will catch you otherwise).
- [ ] Spec referenced in this MR matches the change scope; if the change is behavioural, the spec is at `approved` status.

## Scope

<!-- Sub-modules touched. Breaking change to inputs/outputs? -->

## Checklist

- [ ] CHANGELOG entry under `[Unreleased]`.
- [ ] No `Co-Authored-By: <AI>` trailers; the committing developer owns the change.
