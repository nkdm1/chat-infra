include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/operator-redis-access"
}

locals {
  env = basename(dirname(get_terragrunt_dir()))
}

dependency "resource_group" {
  config_path = "../resource-group"
}

dependency "operator" {
  config_path = "../operator-access"
}

dependency "redis" {
  config_path = "../redis"
}

inputs = {
  role_name             = "chat-${local.env}-operator-redis-key-reader"
  resource_group_id     = dependency.resource_group.outputs.id
  redis_resource_id     = dependency.redis.outputs.id
  operator_principal_id = dependency.operator.outputs.principal_id
}
