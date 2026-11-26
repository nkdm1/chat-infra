include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_path_to_repo_root()}//modules/operator-vault-private-endpoint"
}

locals {
  env                 = basename(dirname(get_terragrunt_dir()))
  subscription_id     = include.root.locals.subscription_id
  operator_vault_name = "chat-ops-cf816eae-kv"
  operator_vault_id   = "/subscriptions/${local.subscription_id}/resourceGroups/chat-shared-rg/providers/Microsoft.KeyVault/vaults/${local.operator_vault_name}"
}

dependency "resource_group" {
  config_path = "../resource-group"
}

dependency "network" {
  config_path = "../network"
}

dependency "key_vault_private_endpoint" {
  config_path = "../key-vault-private-endpoint"
}

inputs = {
  name                = "chat-${local.env}-operator-vault-pe"
  location            = "belgiumcentral"
  resource_group_name = dependency.resource_group.outputs.name
  subnet_id           = dependency.network.outputs.private_endpoint_subnet_id
  vault_id            = local.operator_vault_id
  private_dns_zone_id = dependency.key_vault_private_endpoint.outputs.private_dns_zone_id
  env                 = local.env
}
