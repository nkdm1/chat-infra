include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/operator-secret-access"
}

dependency "operator" {
  config_path = "../operator-access"
}

dependency "key_vault" {
  config_path = "../key-vault"
}

inputs = {
  key_vault_id          = dependency.key_vault.outputs.id
  operator_principal_id = dependency.operator.outputs.principal_id
}
