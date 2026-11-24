include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_path_to_repo_root()}//modules/redis"
}

locals {
  env                 = basename(dirname(get_terragrunt_dir()))
  subscription_suffix = substr(replace(include.root.locals.subscription_id, "-", ""), 0, 8)
}

dependency "resource_group" {
  config_path = "../resource-group"
}

inputs = {
  name                      = "chat-${local.env}-${local.subscription_suffix}-redis"
  resource_group_name       = dependency.resource_group.outputs.name
  location                  = "polandcentral"
  sku_name                  = "Balanced_B0"
  high_availability_enabled = false
  env                       = local.env
}
