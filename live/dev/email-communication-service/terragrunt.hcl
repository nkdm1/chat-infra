include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/email-communication-service"
}

locals {
  env = basename(dirname(get_terragrunt_dir()))
}

dependency "resource_group" {
  config_path = "../resource-group"
}

inputs = {
  name                = "chat-${local.env}-email"
  resource_group_name = dependency.resource_group.outputs.name
  data_location       = "Europe"
  env                 = local.env
}
