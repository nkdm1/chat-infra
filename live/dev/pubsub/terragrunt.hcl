include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_path_to_repo_root()}//modules/pubsub"
}

locals {
  env                 = basename(dirname(get_terragrunt_dir()))
  subscription_suffix = substr(replace(include.root.locals.subscription_id, "-", ""), 0, 8)
}

dependency "resource_group" {
  config_path = "../resource-group"
}

dependency "network" {
  config_path = "../network"
}

dependency "workload_identity" {
  config_path = "../workload-identity"
}

inputs = {
  name                = "chat-${local.env}-${local.subscription_suffix}-wps"
  resource_group_id   = dependency.resource_group.outputs.id
  resource_group_name = dependency.resource_group.outputs.name
  location            = "polandcentral"
  sku_name            = get_env("WEBPUBSUB_SKU")
  subnet_id           = dependency.network.outputs.private_endpoint_subnet_id
  virtual_network_id  = dependency.network.outputs.virtual_network_id
  app_principal_id    = dependency.workload_identity.outputs.principal_id
  env                 = local.env
}
