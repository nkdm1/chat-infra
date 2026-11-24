include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_path_to_repo_root()}//modules/blob-storage"
}

locals {
  env                 = basename(dirname(get_terragrunt_dir()))
  subscription_suffix = substr(replace(include.root.locals.subscription_id, "-", ""), 0, 8)
}

dependency "resource_group" {
  config_path = "../resource-group"
}

dependency "workload_identity" {
  config_path = "../workload-identity"
}

inputs = {
  name             = "chat${local.env}${local.subscription_suffix}st"
  rg-name          = dependency.resource_group.outputs.name
  location         = "spaincentral"
  app_principal_id = dependency.workload_identity.outputs.principal_id
  env              = local.env
}
