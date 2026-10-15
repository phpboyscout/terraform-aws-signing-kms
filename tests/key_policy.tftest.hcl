# Renders the real key policy document offline. Every resource and every
# data source that would call AWS is overridden, so only the
# aws_iam_policy_document data sources are evaluated, and they compute
# locally.

provider "aws" {
  region                      = "eu-west-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_data {
  target = data.aws_partition.current
  values = { partition = "aws" }
}

override_resource {
  target = aws_iam_role.signer
  values = { arn = "arn:aws:iam::111111111111:role/test-signing-signer" }
}

override_resource {
  target = aws_kms_key.this
  values = { arn = "arn:aws:kms:eu-west-2:111111111111:key/test", key_id = "test" }
}

override_resource {
  target = aws_kms_alias.this
}

variables {
  name                   = "test-signing"
  oidc_provider_arn      = "arn:aws:iam::111111111111:oidc-provider/gitlab.com"
  ci_subject_filters     = ["project_path:phpboyscout/example:ref_type:tag:ref:v*"]
  key_administrator_arns = ["arn:aws:iam::111111111111:role/operator"]
  automation_role_arn    = "arn:aws:iam::111111111111:role/infra-apply"
}

run "key_policy" {
  command = apply

  assert {
    condition = one([
      for s in jsondecode(data.aws_iam_policy_document.key_policy.json).Statement : s
      if s.Sid == "DenySignExceptSigner"
      && s.Effect == "Deny"
      && s.Action == "kms:Sign"
      && s.Condition.ArnNotEquals["aws:PrincipalArn"] == "arn:aws:iam::111111111111:role/test-signing-signer"
    ]) != null
    error_message = "every principal but the signer role must be denied kms:Sign"
  }

  assert {
    condition = one([
      for s in jsondecode(data.aws_iam_policy_document.key_policy.json).Statement : s
      if s.Sid == "DenyPutKeyPolicyExceptAutomation"
      && s.Effect == "Deny"
      && s.Action == "kms:PutKeyPolicy"
      && s.Condition.ArnNotEquals["aws:PrincipalArn"] == "arn:aws:iam::111111111111:role/infra-apply"
    ]) != null
    error_message = "every principal but the automation role must be denied kms:PutKeyPolicy"
  }

  assert {
    condition = alltrue([
      for a in one([
        for s in jsondecode(data.aws_iam_policy_document.key_policy.json).Statement : s.Action
        if s.Sid == "KeyAdministrators"
      ]) : !contains(["kms:Sign", "kms:GetPublicKey", "kms:PutKeyPolicy", "kms:CreateGrant"], a) && !strcontains(a, "*")
    ])
    error_message = "KeyAdministrators must be an explicit list without Sign, GetPublicKey, PutKeyPolicy, CreateGrant or wildcards"
  }
}
