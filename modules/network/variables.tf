variable "location" {
  type        = string
  description = "Azure region for the virtual network and network security group."
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group for the network resources."
}

variable "vnet_name" {
  type = string
}

variable "aks_subnet_name" {
  type = string
}
variable "vnet_address_space" {
  type = list(string)
}

variable "subnet_address_prefixes" {
  type = list(string)
}

variable "private_endpoint_subnet_name" {
  type        = string
  description = "Name of the subnet reserved for future private endpoints."
}

variable "private_endpoint_subnet_address_prefixes" {
  type        = list(string)
  description = "CIDR prefixes for the dedicated private-endpoint subnet."
}
