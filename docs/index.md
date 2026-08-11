---
title: terraform-aws-signing-kms
description: Reusable OpenTofu/Terraform module — AWS KMS asymmetric signing key + GitLab-OIDC signer role for release-binary signing chains.
date: 2026-06-01
tags: [overview, introduction]
authors: [Matt Cockayne <matt@phpboyscout.com>]
hide:
  - navigation
---

# terraform-aws-signing-kms

A small, focused [OpenTofu](https://opentofu.org/) / Terraform module that
provisions an AWS KMS asymmetric signing key plus an IAM role assumable
from an external OIDC IDP (default: GitLab.com). Built for release-binary
signing chains where:

- The private key never leaves AWS KMS.
- No human and no long-lived credential can sign — only the CI job
  whose OIDC `sub` claim matches a caller-supplied pattern.
- The apply role that manages the infrastructure cannot mint
  signatures, even on a full compromise of the apply runner.

Sibling to
[`terraform-aws-bootstrap`](https://gitlab.com/phpboyscout/terraform-aws-bootstrap)
(state backend + OIDC IDP) and
[`terraform-aws-security-baseline`](https://gitlab.com/phpboyscout/terraform-aws-security-baseline)
(account hardening + operator role). This module composes after both.

## Start here

- **[Quick start](https://gitlab.com/phpboyscout/terraform-aws-signing-kms#usage)** —
  one-call usage in the README.
- **[v0.1 design spec](development/specs/2026-06-01-signing-kms-v0.1.md)** —
  scope decisions, the permission-class split, and rejected alternatives.
- **[Engineering standards](development/engineering-standards.md)** — module
  conventions, the tag-propagation rule, naming, security defaults.

## Related projects

- **[`phpboyscout/infra`](https://gitlab.com/phpboyscout/infra)** — the
  first user of this module: provisions the
  `gtb-release-signing-v1` key for `phpboyscout/go-tool-base`'s Phase 2
  signed-update pipeline.
- **[`go-tool-base`](https://gitlab.com/phpboyscout/go-tool-base)** —
  the consuming tool, whose `Phase 2 signing prep` document describes
  the wider trust model the AWS half implements.

## Further reading

The blog carries a curated route through this subject: **[Infrastructure with AWS and OpenTofu](https://phpboyscout.uk/topics/infrastructure/)** collects
everything written about it, ordered so you can start at the beginning rather
than newest-first.

!!! tip "Ask phpbotscout"

    ![phpbotscout](https://phpboyscout.uk/images/projects/logo-phpbotscout.png){ width="84" align=left style="border-radius:10px;margin-right:1rem" }

    He answers questions about the projects over on the Discord, citing the docs
    where they already cover it, and offering to raise an issue where they don't.
    Bring a bug, an idea, or a questionable engineering decision.

    [Join the Discord](https://discord.gg/mQzGbmGyzZ){ .md-button .md-button--primary }
