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
  of OIDC `sub` patterns (GitLab or GitHub Actions; e.g.
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
      # Must equal var.oidc_audience (default: sts.amazonaws.com) AND
      # be on the IAM OIDC provider's client_id_list. See the
      # module's docs/development/engineering-standards.md §2.
      aud: sts.amazonaws.com
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

### GitHub Actions

The module is forge-agnostic (GitHub `sub` support since v0.1.2): point it
at the GitHub OIDC provider, set the issuer host, and use GitHub's `sub`
claim format.

```hcl
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

module "signing_kms" {
  source  = "gitlab.com/phpboyscout/signing-kms/aws"
  version = "0.1.2"

  name              = "gtb-release-signing-v1"
  oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn
  oidc_issuer_host  = "token.actions.githubusercontent.com"

  ci_subject_filters = [
    "repo:phpboyscout/go-tool-base:ref:refs/tags/v*",
  ]

  key_administrator_arns = [/* ... */]
  automation_role_arn    = data.aws_iam_role.automation.arn
}
```

The release workflow federates in with the official action (`aud` defaults
to `sts.amazonaws.com`, matching `oidc_audience`):

```yaml
permissions:
  id-token: write
  contents: write
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.SIGNER_ROLE_ARN }}
          aws-region: eu-west-2
          audience: sts.amazonaws.com
      - run: goreleaser release --clean
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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.15.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.signer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_automation_role_arn"></a> [automation\_role\_arn](#input\_automation\_role\_arn) | ARN of the IAM role the infra apply pipeline assumes. Granted the KMS permissions needed to *manage* the key resource via Terraform (Describe, Get, List, Tag, Put-policy, schedule deletion). Deliberately NOT granted `kms:Sign` — a compromise of the apply role must not let an attacker mint signatures. | `string` | n/a | yes |
| <a name="input_ci_subject_filters"></a> [ci\_subject\_filters](#input\_ci\_subject\_filters) | List of OIDC `sub` claim patterns the role accepts (GitLab or GitHub Actions). Wildcards (`*`) are matched with `StringLike`. The canonical scope for a release signer is one tag-pipeline pattern per consuming project — GitLab: `project_path:phpboyscout/go-tool-base:ref_type:tag:ref:v*`; GitHub: `repo:phpboyscout/go-tool-base:ref:refs/tags/v*` — allowing tag pipelines for any `v*` ref while rejecting branch/MR/PR pipelines. Pair with the matching `oidc_issuer_host` and `oidc_provider_arn`. Must be non-empty. | `list(string)` | n/a | yes |
| <a name="input_deletion_window_in_days"></a> [deletion\_window\_in\_days](#input\_deletion\_window\_in\_days) | Number of days AWS KMS waits between schedule-deletion and actual deletion. Range 7-30. Defaults to the maximum (30) — for a signing key, the longest possible recovery window is the safest default. | `number` | `30` | no |
| <a name="input_description"></a> [description](#input\_description) | Human-readable description applied to the KMS key. Shown in the AWS console and in CloudTrail events; useful for auditors. Defaults to a generic string referencing the key's purpose. | `string` | `"Release-binary signing key"` | no |
| <a name="input_key_administrator_arns"></a> [key\_administrator\_arns](#input\_key\_administrator\_arns) | Principal ARNs that may administer the key — schedule deletion, rotate policy, etc. Typically the operator role from `terraform-aws-security-baseline` plus the AWS account root. Used for break-glass; not used in normal operation. The signer role is intentionally NOT an administrator. | `list(string)` | n/a | yes |
| <a name="input_key_spec"></a> [key\_spec](#input\_key\_spec) | KMS asymmetric key spec. Must be a SIGN\_VERIFY-capable spec. AWS KMS does not expose Ed25519 for asymmetric signing, so RSA\_4096 is the secure default. ECC\_NIST\_P256 / P384 / P521 are accepted for callers that prefer EC signatures, but be aware OpenPGP packet encoding is tightly bound to the algorithm — RSA is the right choice for the go-tool-base / OpenPGP signing workflow this module was built for. | `string` | `"RSA_4096"` | no |
| <a name="input_name"></a> [name](#input\_name) | Short kebab-case identifier for this signing key. Used to derive the IAM role name (`<name>-signer`) and the KMS alias (`alias/<name>`). Pick something descriptive that survives key rotation — e.g. `gtb-release-signing-v1` rather than `gtb-release-signing`. | `string` | n/a | yes |
| <a name="input_oidc_audience"></a> [oidc\_audience](#input\_oidc\_audience) | OIDC `aud` claim value the token must carry. The downstream CI job (GitLab `id_tokens:` block, GitHub Actions `audience:` parameter, etc.) declares this audience so the runner gets a token the role accepts. Defaults to `sts.amazonaws.com`, the AWS-side canonical value for `AssumeRoleWithWebIdentity` — also the convention this module's `docs/development/engineering-standards.md` §2 already mandates, and the default `client_id_list` of the sibling `terraform-aws-bootstrap` module's `automation-iam`. IAM OIDC providers reject any JWT whose `aud` isn't on their `client_id_list`, so the two must agree; override only when pairing with a non-standard IAM OIDC provider. | `string` | `"sts.amazonaws.com"` | no |
| <a name="input_oidc_issuer_host"></a> [oidc\_issuer\_host](#input\_oidc\_issuer\_host) | Hostname of the OIDC issuer, used as the prefix on the `aud` / `sub` condition keys (e.g. `gitlab.com:aud`). Defaults to `gitlab.com`. For GitHub Actions set `token.actions.githubusercontent.com`; for self-managed GitLab, your instance host. | `string` | `"gitlab.com"` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the IAM OIDC identity provider whose tokens this role trusts. Typically the GitLab OIDC IDP provisioned by `terraform-aws-bootstrap` (output `oidc_provider_arn`). Pass via a `data.aws_iam_openid_connect_provider` lookup so the caller does not hardcode the ARN. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to every taggable resource. Merged with `Component = "signing-kms"` per the module-repo convention. Cross-cutting tags (Project, ManagedBy, Repository) come from the consuming stack's provider `default_tags`. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_key_alias_arn"></a> [key\_alias\_arn](#output\_key\_alias\_arn) | ARN of the KMS alias resource. Rarely needed directly; useful for IAM policies that allow alias-based access (a pattern this module does not adopt but downstream callers might). |
| <a name="output_key_alias_name"></a> [key\_alias\_name](#output\_key\_alias\_name) | Full KMS alias (e.g. `alias/<name>`). Pass to `aws kms sign --key-id` and into the signing shim script's `--key-id` argument. Survives key rotation: when v2 is minted the alias is repointed in a separate apply. |
| <a name="output_key_arn"></a> [key\_arn](#output\_key\_arn) | Full KMS key ARN. Use in IAM policy `Resource` blocks when an attached resource policy needs to reference this specific key. Run-time signers should still prefer `key_alias_name`. |
| <a name="output_key_id"></a> [key\_id](#output\_key\_id) | Bare KMS key ID. Prefer `key_alias_name` for run-time references — the alias survives key rotation. |
| <a name="output_signer_role_arn"></a> [signer\_role\_arn](#output\_signer\_role\_arn) | ARN of the signer IAM role. Set this as `AWS_ROLE_ARN` in the consuming `.gitlab-ci.yml`'s goreleaser job. The job must also declare `id_tokens:` with `aud = var.oidc_audience`. |
| <a name="output_signer_role_name"></a> [signer\_role\_name](#output\_signer\_role\_name) | Bare name of the signer IAM role. Useful for diagnostic CLI calls (`aws iam get-role --role-name ...`); production wiring should use `signer_role_arn`. |
<!-- END_TF_DOCS -->

## License

MIT — see [LICENSE](./LICENSE).
