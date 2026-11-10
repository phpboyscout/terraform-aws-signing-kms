# Changelog

## [v0.3.0](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/releases/v0.3.0)

[Compare to previous version](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/compare/v0.2.3...v0.3.0)

### Notes

- New input mint_principal_arns, empty by default, exempts a human key-ceremony role from the signer-only Sign Deny, narrowed to a DIGEST with RSASSA_PKCS1_V1_5_SHA_256. Nothing changes for a caller that leaves it unset.

### Features

- let a named ceremony role mint the key's OpenPGP identity ([6092548](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/commit/6092548a79f9a0aaa9ff384a96e526e29e955a9c))

### Bug Fixes

- stop the README claiming no human can sign, and refuse wildcard mint principals ([f3c0039](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/commit/f3c003999dc5d64ef94602272db1726f0c78608f))

## [v0.2.3](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/releases/v0.2.3)

[Compare to previous version](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/compare/v0.2.2...v0.2.3)

### Notes

- The key policy now reserves signing for the signer role and key-policy changes for the automation role. Apply this module as the automation role; see "Break-glass" in the README.

### Bug Fixes

- deny signing and key-policy changes to all but their roles ([01ada62](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/commit/01ada62a0c94dc25481a655d193bbd392d7a9f9e))

## [v0.2.2](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/releases/v0.2.2)

[Compare to previous version](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/compare/v0.2.1...v0.2.2)

### Notes

- The declared `required_version` is widened from `~> 1.15.0` to the floor `>= 1.5.0`, the oldest version the module supports. OpenTofu 1.12 and later do not enforce it in a `.tf` file, and Terraform users on any release from 1.5 onward are no longer refused. CI still tests on the OpenTofu release pinned in `.opentofu-version`.

- Releases are announced to the estate's release feed.

### Bug Fixes

- declare required_version as the floor >= 1.5.0 ([d15072c](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/commit/d15072c9a952265ee570c6d8c264c692e39133f0))

## [v0.2.1](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/releases/v0.2.1)

[Compare to previous version](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/compare/v0.2.0...v0.2.1)

### Bug Fixes

- **ci**: publish on tag from a real stage, not .post ([3dd9b9f](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/commit/3dd9b9f7ff490f8156342403ca72fc3767c13829))

## [v0.2.0](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/releases/v0.2.0)

[Compare to previous version](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/compare/v0.1.2...v0.2.0)

### Features

- accept ECC_NIST_EDWARDS25519 for minisign artefact signing ([bee95fa](https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms/-/commit/bee95fa8bc3f779812e38ce4f06f68097dde161c))

## [v0.1.2](https://gitlab.com/phpboyscout/terraform-aws-signing-kms/-/releases/v0.1.2)

### Bug Fixes

- **oidc**: accept GitHub Actions sub claims in ci_subject_filters

## [v0.1.1](https://gitlab.com/phpboyscout/terraform-aws-signing-kms/-/releases/v0.1.1)

### Bug Fixes

- **module**: default oidc_audience to sts.amazonaws.com

## [v0.1.0](https://gitlab.com/phpboyscout/terraform-aws-signing-kms/-/releases/v0.1.0)

### Features

- **module**: initial release — KMS signing key + GitLab-OIDC signer role

### Bug Fixes

- **module**: add checkov skip directives to KMS key policy

All notable changes to this project are documented in this file.

This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.
Entries are maintained by [releaser-pleaser](https://releaser-pleaser.dev/)
on every release MR merge.

## [Unreleased]
