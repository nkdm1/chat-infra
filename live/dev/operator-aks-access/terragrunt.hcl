include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/operator-aks-access"
}

locals {
  env = basename(dirname(get_terragrunt_dir()))
}

dependency "aks" {
  config_path = "../aks"
}

dependency "operator" {
  config_path = "../operator-access"
}

dependency "postgresql_network" {
  config_path = "../postgresql-network"
}

inputs = {
  aks_id                      = dependency.aks.outputs.id
  operator_principal_id       = dependency.operator.outputs.principal_id
  operator_virtual_network_id = dependency.postgresql_network.outputs.virtual_network_id
  dns_link_name               = "chat-${local.env}-operator-aks-vnet-link"
}
