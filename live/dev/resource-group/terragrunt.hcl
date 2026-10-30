include "env_config" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/resource-group"
}

inputs = {
  name     = "chat-${local.env}-rg"
  location = "polandcentral"
  env      = local.env
}
