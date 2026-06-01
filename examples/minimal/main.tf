################################################################################
# examples/minimal — `tofu validate` fixture for terraform-aws-signing-kms.
#
# Demonstrates the module's caller contract with placeholder ARNs that
# match the regex validations on every input. This example is not meant
# to be applied — the OIDC provider ARN, administrator ARN, and
# automation role ARN are fake. CI runs `tofu init -backend=false &&
# tofu validate` against this dir to confirm the module's interface is
# well-formed.
#
# To use the module in a real stack, see ../../README.md.
################################################################################

terraform {
  required_version = "~> 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region                      = "eu-west-2"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  # Don't enforce account ID — this example is for validate-only.
}

module "signing_kms" {
  source = "../.."

  name        = "example-signing-v1"
  description = "Example signing key for terraform-aws-signing-kms validate-only fixture"

  oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/gitlab.com"

  ci_subject_filters = [
    "project_path:example/repo:ref_type:tag:ref:v*",
  ]

  key_administrator_arns = [
    "arn:aws:iam::000000000000:role/example-admin",
    "arn:aws:iam::000000000000:root",
  ]

  automation_role_arn = "arn:aws:iam::000000000000:role/example-automation"

  tags = {
    Project    = "example"
    ManagedBy  = "opentofu"
    Repository = "example/repo"
  }
}
