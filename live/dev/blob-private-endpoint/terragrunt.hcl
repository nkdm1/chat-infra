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

dependency "blob_storage" {
  config_path = "../blob-storage"
}

inputs = {
  name                  = "chat-${local.env}-blob-pe"
  location              = "polandcentral"
  resource_group_name   = dependency.resource_group.outputs.name
  subnet_id             = dependency.network.outputs.private_endpoint_subnet_id
  virtual_network_id    = dependency.network.outputs.virtual_network_id
  target_resource_id    = dependency.blob_storage.outputs.storage_account_id
  subresource_name      = "blob"
  private_dns_zone_name = "privatelink.blob.core.windows.net"
  env                   = local.env
}
