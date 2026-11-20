include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_path_to_repo_root()}//modules/cosmos-db-account"
}

locals {
  env = basename(dirname(get_terragrunt_dir()))
  subscription_suffix = substr(replace(include.root.locals.subscription_id, "-", ""), 0, 8)
}

dependency "resource_group" {
  config_path = "../resource-group"
}

inputs = {
  account_name        = "chat-cosmos-${local.subscription_suffix}"
  location            = "polandcentral"
  resource_group_name = dependency.resource_group.outputs.name
  free_tier_enabled   = true
  env                 = local.env
}
