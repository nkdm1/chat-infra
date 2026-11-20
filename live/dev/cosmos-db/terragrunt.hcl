include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/cosmos-db-namespace"
}

locals {
  env = basename(dirname(get_terragrunt_dir()))
}

dependency "shared_cosmos_db_account" {
  config_path = "../../shared/cosmos-db-account"
}

inputs = {
  account_id          = dependency.shared_cosmos_db_account.outputs.id
  account_name        = dependency.shared_cosmos_db_account.outputs.name
  endpoint            = dependency.shared_cosmos_db_account.outputs.endpoint
  resource_group_name = dependency.shared_cosmos_db_account.outputs.resource_group_name
  database_name       = "chat-${local.env}"
  container_name      = "messages"
  throughput          = 400
  #TODO: sub this with a real workload identity later
  app_principal_id = null
}
