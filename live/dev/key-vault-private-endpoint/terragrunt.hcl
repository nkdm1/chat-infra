include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/private-endpoint"
}

locals {
  env = basename(dirname(get_terragrunt_dir()))
}

dependency "resource_group" {
  config_path = "../resource-group"
}

dependency "network" {
  config_path = "../network"
}

dependency "key_vault" {
  config_path = "../key-vault"
}

dependency "postgresql_network" {
  config_path = "../postgresql-network"
}

inputs = {
  name                           = "chat-${local.env}-vault-pe"
  location                       = "belgiumcentral"
  resource_group_name            = dependency.resource_group.outputs.name
  subnet_id                      = dependency.network.outputs.private_endpoint_subnet_id
  virtual_network_id             = dependency.network.outputs.virtual_network_id
  additional_virtual_network_ids = { denmark = dependency.postgresql_network.outputs.virtual_network_id }
  target_resource_id             = dependency.key_vault.outputs.id
  subresource_name               = "vault"
  private_dns_zone_name          = "privatelink.vaultcore.azure.net"
  env                            = local.env
}
