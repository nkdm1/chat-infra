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

dependency "workload_identity" {
  config_path = "../workload-identity"
}

inputs = {
  name                       = "chat-${local.env}-email"
  communication_service_name = "chat-${local.env}-acs"
  resource_group_name        = dependency.resource_group.outputs.name
  resource_group_id          = dependency.resource_group.outputs.id
  app_principal_id           = dependency.workload_identity.outputs.principal_id
  data_location              = "Europe"
  env                        = local.env
}
