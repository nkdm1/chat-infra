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

dependency "postgresql_network" {
  config_path = "../postgresql-network"
}

# scripts/infra-up.sh supplies this as an ephemeral process environment value
# through scripts/terragrunt_with_postgres_admin_secret.py. Never pass it through
# Terragrunt inputs or write it to state.
inputs = {
  name                           = "chat-${local.env}-${local.subscription_suffix}-dk-pg"
  dns_link_name_prefix           = "chat-${local.env}-${local.subscription_suffix}-pg"
  resource_group_name            = dependency.resource_group.outputs.name
  location                       = "denmarkeast"
  delegated_subnet_id            = dependency.postgresql_network.outputs.postgresql_subnet_id
  virtual_network_id             = dependency.network.outputs.virtual_network_id
  additional_virtual_network_ids = { denmark = dependency.postgresql_network.outputs.virtual_network_id }
  private_dns_zone_name          = "chat-${local.env}.postgres.database.azure.com"
  postgresql_version             = "17"
  sku_name                       = get_env("POSTGRESQL_SKU", "B_Standard_B1ms")
  storage_mb                     = 32768
  backup_retention_days          = 7
  administrator_login            = "chatadmin"
  administrator_password_version = 1
  env                            = local.env
}
