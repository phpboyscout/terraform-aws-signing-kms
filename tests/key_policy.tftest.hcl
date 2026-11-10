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

run "no_mint_principal_by_default" {
  command = apply

  assert {
    condition = length([
      for s in jsondecode(data.aws_iam_policy_document.key_policy.json).Statement : s
      if s.Sid == "MintSign"
    ]) == 0
    error_message = "MintSign must be absent when mint_principal_arns is empty"
  }

  assert {
    condition = length([
      for s in jsondecode(data.aws_iam_policy_document.key_policy.json).Statement : s
      if startswith(s.Sid, "DenyMintSign")
    ]) == 0
    error_message = "the mint Denies must be absent when mint_principal_arns is empty"
  }
}

run "mint_principal_may_sign" {
  command = apply

  variables {
    mint_principal_arns = ["arn:aws:iam::111111111111:role/pbs-test-key-ceremony"]
  }

  assert {
    condition = one([
      for s in jsondecode(data.aws_iam_policy_document.key_policy.json).Statement : s
      if s.Sid == "MintSign"
      && s.Effect == "Allow"
      && s.Principal.AWS == "arn:aws:iam::111111111111:role/pbs-test-key-ceremony"
      && contains(s.Action, "kms:Sign")
    ]) != null
    error_message = "a mint principal must be allowed kms:Sign"
  }

  assert {
    condition = one([
      for s in jsondecode(data.aws_iam_policy_document.key_policy.json).Statement : s
      if s.Sid == "DenySignExceptSigner"
      && toset(s.Condition.ArnNotEquals["aws:PrincipalArn"]) == toset([
        "arn:aws:iam::111111111111:role/test-signing-signer",
        "arn:aws:iam::111111111111:role/pbs-test-key-ceremony",
      ])
    ]) != null
    error_message = "the Sign Deny must except the signer role and the mint principal, and no one else"
  }

  assert {
    condition = one([
      for s in jsondecode(data.aws_iam_policy_document.key_policy.json).Statement : s
      if s.Sid == "DenyMintSignExceptDigest"
      && s.Effect == "Deny"
      && s.Condition.ArnEquals["aws:PrincipalArn"] == "arn:aws:iam::111111111111:role/pbs-test-key-ceremony"
      && s.Condition.StringNotEquals["kms:MessageType"] == "DIGEST"
    ]) != null
    error_message = "a mint principal must be denied Sign on anything but a DIGEST"
  }

  assert {
    condition = one([
      for s in jsondecode(data.aws_iam_policy_document.key_policy.json).Statement : s
      if s.Sid == "DenyMintSignExceptDigestSha256"
      && s.Effect == "Deny"
      && s.Condition.ArnEquals["aws:PrincipalArn"] == "arn:aws:iam::111111111111:role/pbs-test-key-ceremony"
      && s.Condition.StringNotEquals["kms:SigningAlgorithm"] == "RSASSA_PKCS1_V1_5_SHA_256"
    ]) != null
    error_message = "a mint principal must be denied Sign with any algorithm but RSASSA_PKCS1_V1_5_SHA_256"
  }
}
