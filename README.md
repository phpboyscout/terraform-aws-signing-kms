# terraform-aws-signing-kms

> ⚠️ Pre-1.0. API will move. Pin to a tag, not a branch.

Reusable [OpenTofu](https://opentofu.org/) / Terraform module that
provisions an AWS KMS asymmetric signing key plus an IAM role
assumable from an external OIDC IDP (default: GitLab.com). Built for
release-binary signing chains where:

- The private key never leaves AWS KMS.
- No human and no long-lived credential can sign — only the CI job
  whose OIDC `sub` claim matches a caller-supplied pattern.
- The apply role that manages the infrastructure cannot mint
  signatures, even on a full compromise of the apply runner.

Sibling to
[`terraform-aws-bootstrap`](https://gitlab.com/phpboyscout/terraform-aws-bootstrap)
(state backend + OIDC IDP + automation role) and
[`terraform-aws-security-baseline`](https://gitlab.com/phpboyscout/terraform-aws-security-baseline)
(account hardening, operator role, alerts). This module composes
**after** those two: it consumes the OIDC IDP they registered and
delegates `KeyAdministrator` to the operator role they minted.

## What's in scope

- One asymmetric KMS key (default `RSA_4096`, `SIGN_VERIFY`) with a
  stable alias and a 30-day deletion window.
- One IAM role whose trust policy is scoped via `StringLike` to a list
  of GitLab OIDC `sub` patterns (e.g.
  `project_path:phpboyscout/go-tool-base:ref_type:tag:ref:v*`).
- A key policy that names four principal classes — account root,
  administrators, automation, signer — and grants each exactly what
  it needs. The signer role has no attached IAM policy; the key policy
  is the single source of permission grants.

## What's out of scope

- **The OIDC IDP itself.** `terraform-aws-bootstrap` registers it; this
  module references its ARN.
- **The Web Key Directory.** Cross-platform release verification needs
  an external trust anchor (e.g. WKD on Cloudflare Pages) administered
  independently of AWS. Provisioning it here would collapse that
  separation.
- **The signing shim.** GoReleaser's `signs:` block shells out to a
  script the caller writes (`scripts/sign-release.sh`). The shim
  abstracts whether the key lives in KMS, on a YubiKey, or in a local
  GPG keyring; the consumer owns it.
- **Key rotation orchestration.** Rotate by minting a second module
  instance (`<name>-v2`), dual-signing during the support window, then
  deleting the v1 module instance. The module is intentionally
  immutable for the `key_spec` and `name` inputs.

## Usage

```hcl
data "aws_iam_openid_connect_provider" "gitlab" {
  url = "https://gitlab.com"
}

module "signing_kms" {
  source  = "gitlab.com/phpboyscout/signing-kms/aws"
  version = "0.1.0"

  name        = "gtb-release-signing-v1"
  description = "go-tool-base release binary signing (Phase 2)"

  oidc_provider_arn = data.aws_iam_openid_connect_provider.gitlab.arn

  ci_subject_filters = [
    "project_path:phpboyscout/go-tool-base:ref_type:tag:ref:v*",
  ]

  key_administrator_arns = [
    module.security_baseline.operator_role_arn,
    "arn:aws:iam::${var.account_id}:root",
  ]
  automation_role_arn = data.aws_iam_role.automation.arn
}

output "signer_role_arn" {
  value = module.signing_kms.signer_role_arn
}

output "signing_key_alias" {
  value = module.signing_kms.key_alias_name
}
```

The consuming `.gitlab-ci.yml` then wires the role + key into the
release job:

```yaml
goreleaser:
  rules:
    - if: '$CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/'
  id_tokens:
    AWS_WEB_IDENTITY_TOKEN:
      aud: https://gitlab.com
  variables:
    AWS_REGION: eu-west-2
    AWS_ROLE_ARN: ${SIGNER_ROLE_ARN}
    AWS_WEB_IDENTITY_TOKEN_FILE: /tmp/aws-token
    GTB_SIGNING_KEY: ${SIGNING_KEY_ALIAS}
  before_script:
    - echo "$AWS_WEB_IDENTITY_TOKEN" > /tmp/aws-token
  script:
    - goreleaser release --clean
```

## Design

See [docs/development/specs/2026-06-01-signing-kms-v0.1.md](docs/development/specs/2026-06-01-signing-kms-v0.1.md)
for the full design record. The headline decisions:

- **Key spec**: `RSA_4096`, `SIGN_VERIFY`. Ed25519 is not exposed by
  AWS KMS for asymmetric signing.
- **Signing algorithm**: caller's choice at sign time — the key
  policy does not restrict `kms:SigningAlgorithm`. OpenPGP packet
  encoding prefers `RSASSA_PKCS1_V1_5_SHA_256`; non-OpenPGP envelopes
  may prefer PSS.
- **OIDC subject scope**: caller passes the full `StringLike` patterns
  for `<issuer>:sub`. The canonical scope is one tag-pipeline pattern
  per consuming project; MR and branch pipelines are deliberately
  excluded.
- **Permission split**: signer (Sign / GetPublicKey / DescribeKey),
  administrators (everything except Sign and PutKeyPolicy), automation
  (manage as a Terraform resource — including PutKeyPolicy — but not
  Sign).
- **No attached IAM policy on the signer role**. The key policy is the
  single source of grants. Avoids key-policy / role-policy drift.

## Inputs

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs writes the inputs/outputs tables here. Run
     `just docs` (when added) or rely on the CI terraform-docs job. -->
<!-- END_TF_DOCS -->

## License

MIT — see [LICENSE](./LICENSE).
