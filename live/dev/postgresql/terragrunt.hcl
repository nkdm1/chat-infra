include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_path_to_repo_root()}//modules/postgresql"
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

# The operator supplies TF_VAR_administrator_password securely; it is ephemeral
# and must not be passed through Terragrunt inputs or written to state.
inputs = {
  name                           = "chat-${local.env}-${local.subscription_suffix}-pg"
  resource_group_name            = dependency.resource_group.outputs.name
  location                       = "spaincentral"
  delegated_subnet_id            = dependency.network.outputs.postgresql_subnet_id
  virtual_network_id             = dependency.network.outputs.virtual_network_id
  private_dns_zone_name          = "chat-${local.env}.postgres.database.azure.com"
  postgresql_version             = "17"
  sku_name                       = get_env("POSTGRESQL_SKU")
  storage_mb                     = 32768
  backup_retention_days          = 7
  administrator_login            = "chatadmin"
  administrator_password_version = 1
  env                            = local.env
}
