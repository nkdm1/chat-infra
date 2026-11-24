variable "resource_group_name" {
  description = "Resource group containing both virtual networks."
  type        = string
}

variable "location" {
  description = "Region for the PostgreSQL virtual network."
  type        = string
}

variable "vnet_name" {
  description = "Name of the PostgreSQL virtual network."
  type        = string
}

variable "address_space" {
  description = "Non-overlapping address space for the PostgreSQL VNet."
  type        = list(string)
}

variable "subnet_name" {
  description = "Name of the PostgreSQL delegated subnet."
  type        = string
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for the delegated subnet."
  type        = list(string)
}

variable "app_virtual_network_id" {
  description = "Resource ID of the existing application VNet."
  type        = string
}

variable "app_virtual_network_name" {
  description = "Name of the existing application VNet in the same resource group."
  type        = string
}

variable "env" {
  description = "Environment name."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  tags = merge(var.tags, { env = var.env })
}
