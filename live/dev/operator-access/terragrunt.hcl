include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/operator-access"
}

locals {
  env = basename(dirname(get_terragrunt_dir()))
}

dependency "resource_group" {
  config_path = "../resource-group"
}

dependency "postgresql_network" {
  config_path = "../postgresql-network"
}

inputs = {
  enable_bastion          = false
  name                    = "chat-${local.env}-operator"
  resource_group_name     = dependency.resource_group.outputs.name
  location                = "denmarkeast"
  virtual_network_id      = dependency.postgresql_network.outputs.virtual_network_id
  virtual_network_name    = "chat-${local.env}-postgresql-vnet"
  subnet_name             = "chat-${local.env}-operator-subnet"
  subnet_address_prefixes = ["10.2.2.0/24"]
  vm_size                 = "Standard_B2ls_v2"
  admin_username          = "chatoperator"
  ssh_public_key          = get_env("OPERATOR_SSH_PUBLIC_KEY")
  env                     = local.env
}
