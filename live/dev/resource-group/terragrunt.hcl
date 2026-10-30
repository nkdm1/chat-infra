include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/resource-group"
}

inputs = {
  name     = "chat-${local.env}-rg"
  location = "polandcentral"
  env      = local.env
}

locals {
  env = basename(dirname(get_terragrunt_dir()))
}

