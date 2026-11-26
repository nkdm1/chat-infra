include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/postgresql-network"
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

inputs = {
  resource_group_name      = dependency.resource_group.outputs.name
  location                 = "denmarkeast"
  vnet_name                = "chat-${local.env}-postgresql-vnet"
  address_space            = ["10.2.0.0/16"]
  subnet_name              = "chat-${local.env}-postgresql-subnet"
  subnet_address_prefixes  = ["10.2.1.0/24"]
  app_virtual_network_id   = dependency.network.outputs.virtual_network_id
  app_virtual_network_name = "chat-${local.env}-vnet"
  env                      = local.env
}
