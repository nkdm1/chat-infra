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

dependency "container_registry" {
  config_path = "../../shared/container-registry"
}

dependency "resource_group" {
  config_path = "../resource-group"
}


inputs = {
  aks_name             = "chat-${local.env}-aks"
  location             = "belgiumcentral"
  resource_group_name  = dependency.resource_group.outputs.name
  dns_prefix           = "chat-${local.env}-aks"
  aks_subnet_id        = dependency.network.outputs.aks_subnet_id
  virtual_network_id   = dependency.network.outputs.virtual_network_id
  egress_public_ip_id  = dependency.network.outputs.egress_public_ip_id
  gateway_public_ip_id = dependency.network.outputs.gateway_public_ip_id

  acr_id = dependency.container_registry.outputs.id

  node_vm_size   = "Standard_D2s_v4"
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
