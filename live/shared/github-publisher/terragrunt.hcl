include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/github-publisher"
}

dependency "resource_group" {
  config_path = "../resource-group"
}

dependency "container_registry" {
  config_path = "../container-registry"
}

inputs = {
  name                = "chat-github-publisher"
  resource_group_name = dependency.resource_group.outputs.name
  location            = "belgiumcentral"
  registry_id         = dependency.container_registry.outputs.id
  github_repository   = "nkdm1/chat"
  github_branch       = "main"
  env                 = "shared"
}
