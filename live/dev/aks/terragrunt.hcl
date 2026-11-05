include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/aks"
}

locals {
  env = basename(dirname(get_terragrunt_dir()))
}

dependency "network" {
  config_path = "../network"
}

dependencies {
  paths = ["../resource-group", "../container-registry"]
}

inputs = {
  aks_name            = "chat-${local.env}-aks"
  location            = "polandcentral"
  resource_group_name = "chat-${local.env}-rg"
  dns_prefix          = "chat-${local.env}-aks"
  aks_subnet_id       = dependency.network.outputs.aks_subnet_id

  # TODO: add acr to modules
  acr_id = get_env("ACR_ID")

  node_vm_size   = "Standard_D2als_v7"
  node_min_count = 1
  node_max_count = 2

  pod_cidr       = "10.2.0.0/22"
  service_cidr   = "10.2.4.0/24"
  dns_service_ip = "10.2.4.10"

  env = local.env
  tags = {
    project = "azure-chat-webapp"
  }
}
