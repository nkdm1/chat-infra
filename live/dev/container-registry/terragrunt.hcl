include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/container-registry"
}

locals {
  env = basename(dirname(get_terragrunt_dir()))
}

dependency "resource_group" {
  config_path = "../resource-group"
}

inputs = {
  name     = "chat-${local.env}-container-registry"
  rg-name  = dependency.resource_group.outputs.name
  location = dependency.resource_group.outputs.location
  env      = local.env
}
