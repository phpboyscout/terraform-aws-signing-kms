# terraform-aws-signing-kms

**An AWS KMS asymmetric signing key, plus the IAM role that lets CI use it.**
Provisions the key and an IAM role assumable from an external OIDC provider
(GitLab.com by default), for release-signing chains where the private half must
never leave KMS and CI must never hold a long-lived credential. Pre-1.0, so pin
to a tag rather than a branch.

> **This is a read-only mirror. The canonical repository is on GitLab:**
> **https://gitlab.com/phpboyscout/iac/terraform-aws-signing-kms**
>
> Issues and merge requests are handled there.

## Using it

Published to GitLab's Terraform module registry, so consume it from there
rather than from a git source:

```hcl
module "signing_kms" {
  source  = "gitlab.com/phpboyscout/signing-kms/aws"
  version = "0.1.0"
}
```

## Documentation

Full documentation: **https://aws-signing-kms.iac.phpboyscout.uk**

The signing model it exists to serve is written up in
[Signing your releases](https://phpboyscout.uk/topics/signing/), including why
the key is generated inside KMS and has no export path.
