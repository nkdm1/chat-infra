include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_path_to_repo_root()}//modules/operator-vault-access"
}

locals {
  subscription_id     = include.root.locals.subscription_id
  operator_vault_name = "chat-ops-cf816eae-kv"
  operator_vault_id   = "/subscriptions/${local.subscription_id}/resourceGroups/chat-shared-rg/providers/Microsoft.KeyVault/vaults/${local.operator_vault_name}"
}

dependency "operator" {
  config_path = "../operator-access"
}

inputs = {
  key_vault_id          = local.operator_vault_id
  operator_principal_id = dependency.operator.outputs.principal_id
}
