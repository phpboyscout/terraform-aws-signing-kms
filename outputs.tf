output "key_id" {
  description = "Bare KMS key ID. Prefer `key_alias_name` for run-time references — the alias survives key rotation."
  value       = aws_kms_key.this.key_id
}

output "key_arn" {
  description = "Full KMS key ARN. Use in IAM policy `Resource` blocks when an attached resource policy needs to reference this specific key. Run-time signers should still prefer `key_alias_name`."
  value       = aws_kms_key.this.arn
}

output "key_alias_name" {
  description = "Full KMS alias (e.g. `alias/<name>`). Pass to `aws kms sign --key-id` and into the signing shim script's `--key-id` argument. Survives key rotation: when v2 is minted the alias is repointed in a separate apply."
  value       = aws_kms_alias.this.name
}

output "key_alias_arn" {
  description = "ARN of the KMS alias resource. Rarely needed directly; useful for IAM policies that allow alias-based access (a pattern this module does not adopt but downstream callers might)."
  value       = aws_kms_alias.this.arn
}

output "signer_role_arn" {
  description = "ARN of the signer IAM role. Set this as `AWS_ROLE_ARN` in the consuming `.gitlab-ci.yml`'s goreleaser job. The job must also declare `id_tokens:` with `aud = var.oidc_audience`."
  value       = aws_iam_role.signer.arn
}

output "signer_role_name" {
  description = "Bare name of the signer IAM role. Useful for diagnostic CLI calls (`aws iam get-role --role-name ...`); production wiring should use `signer_role_arn`."
  value       = aws_iam_role.signer.name
}
