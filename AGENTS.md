# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, agy, codex, etc.) when working with code in this repository.

## Project shape

`phpboyscout/terraform-aws-signing-kms` is a **reusable
OpenTofu/Terraform module** that provisions an AWS KMS asymmetric
signing key plus a GitLab-OIDC-trusted IAM signer role for release
binary signing. Sibling to
[`terraform-aws-bootstrap`](https://gitlab.com/phpboyscout/terraform-aws-bootstrap)
(state backend + OIDC IDP) and
[`terraform-aws-security-baseline`](https://gitlab.com/phpboyscout/terraform-aws-security-baseline)
(account hardening + operator role). This module composes after both.

Single-module repo (no sub-modules). The module HCL sits at the repo
root: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`. An
`examples/minimal/` fixture exercises the caller contract under
`tofu validate` in CI.

**Out of scope** (and why): the OIDC IDP itself (bootstrap owns it),
the WKD endpoint (lives on Cloudflare Pages with credentials
administered independently of AWS, by design), key rotation
orchestration (rotate by minting a second module instance, not by
mutating in place), the signing shim script (consumer-owned).

## Tagging convention

Every taggable resource takes `var.tags` and merges in
`Component = "signing-kms"`:

```hcl
tags = merge(var.tags, { Component = "signing-kms" })
```

Cross-cutting tags (`Project`, `Environment`, `ManagedBy`, `Repository`)
come from the consuming stack's provider `default_tags` block — they
must not be repeated here. New taggable resources MUST follow this
pattern; no exceptions.

## Spec-first discipline

**No HCL lands without a spec it implements.** Specs live in
`docs/development/specs/<YYYY-MM-DD>-<slug>.md` (Zensical-rendered with
status pills). PRs cite the spec they implement; status flows
`draft → approved → implemented`.

Master spec: `2026-06-01-signing-kms-v0.1.md`.

## Tooling

- **OpenTofu version** pinned in `.opentofu-version` (currently
  `1.11.6`). Locally managed via `mise → tenv → tofu`; the mise shim
  dir is `~/.local/share/mise/shims`. In non-interactive shells,
  prepend it.
- **Task runner:** `justfile`.
- **Pre-commit hooks** mirror the CI gate (`just setup` installs them).
- **CI** lives in `.gitlab-ci.yml`: tofu-lint, tofu-security,
  tofu-validate, zensical-pages, tofu-module-publish — all consumed
  from `phpboyscout/cicd` components.

## Branch and commit workflow

Trunk-based: branch from `main`, MR to `main`. Releases via
releaser-pleaser (release MR on `main`; merging it tags `vX.Y.Z` and
publishes to the GitLab module registry).

### Commit Conventions

All commits must follow [Conventional Commits](https://www.conventionalcommits.org/).
`releaser-pleaser` uses these to compute the release version and
changelog.

**Do not commit without explicit user approval.** Present a summary of
changes and a proposed message, then wait for confirmation.

**Do not add AI attribution** — no `Co-Authored-By:` trailers naming an
AI, no references to AI assistance in commit messages. The committing
developer owns the change entirely.

| Type | Release |
|------|---------|
| `feat(scope):` | Minor |
| `fix(scope):` / `perf(scope):` / `refactor(scope):` | Patch |
| `ci:` / `chore:` / `style:` / `docs:` / `test:` | None |
| `BREAKING CHANGE:` footer | Major |

**Scope**: this is a single-module repo, so the scope is typically
`module` for HCL changes (`feat(module):`, `fix(module):`). For
examples use `examples`. For CI/workflows use `ci`. For repo-wide
toolchain changes use `repo`. Each commit represents one coherent
change.

## Where to look for things that aren't obvious

- **Key policy structure**: `main.tf` — four principal classes
  (account root, administrators, automation, signer), each granted
  exactly what it needs. The signer role has no attached IAM policy on
  purpose; see the design spec.
- **Why no IAM role policy**: design spec D5. Key policy is the
  single source of truth; avoids drift.
- **Why no Ed25519**: design spec D1. AWS KMS does not expose Ed25519
  for asymmetric `SIGN_VERIFY` keys.
- **Why no key rotation**: design spec D8. Rotate by minting a v2
  module instance, dual-signing the support window, deleting v1.
