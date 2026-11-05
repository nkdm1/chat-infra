include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}//modules/network"
}

locals {
  env = basename(dirname(get_terragrunt_dir()))
}

dependencies {
  paths = ["../resource-group"]
}

inputs = {
  location            = "polandcentral"
  resource_group_name = "chat-${local.env}-rg"

  vnet_name               = "chat-${local.env}-vnet"
  vnet_address_space      = ["10.1.0.0/16"]
  aks_subnet_name         = "chat-${local.env}-aks-subnet"
  subnet_address_prefixes = ["10.1.1.0/24"]

  private_endpoint_subnet_name             = "chat-${local.env}-private-endpoints-subnet"
  private_endpoint_subnet_address_prefixes = ["10.1.2.0/24"]
}
