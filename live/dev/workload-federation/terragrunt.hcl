include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/workload-federation"
}

dependency "workload_identity" {
  config_path = "../workload-identity"
}

dependency "aks" {
  config_path = "../aks"
}

inputs = {
  name            = "chat-app"
  identity_id     = dependency.workload_identity.outputs.id
  oidc_issuer_url = dependency.aks.outputs.oidc_issuer_url
}
