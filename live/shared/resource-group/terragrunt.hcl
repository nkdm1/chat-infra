include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/resource-group"
}

locals {
  env = basename(dirname(get_terragrunt_dir()))
}

inputs = {
  name     = "chat-shared-rg"
  location = "polandcentral"
  env      = local.env
}
