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

dependency "cosmos" {
  config_path = "../../shared/cosmos-db-account"
}

inputs = {
  name                  = "chat-${local.env}-cosmos-pe"
  location              = "polandcentral"
  resource_group_name   = dependency.resource_group.outputs.name
  subnet_id             = dependency.network.outputs.private_endpoint_subnet_id
  virtual_network_id    = dependency.network.outputs.virtual_network_id
  target_resource_id    = dependency.cosmos.outputs.id
  subresource_name      = "Sql"
  private_dns_zone_name = "privatelink.documents.azure.com"
  env                   = local.env
}
