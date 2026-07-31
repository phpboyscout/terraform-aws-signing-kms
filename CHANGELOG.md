# Changelog

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
