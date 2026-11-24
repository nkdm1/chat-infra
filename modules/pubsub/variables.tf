variable "name" {
  description = "Globally unique Web PubSub service name."
  type        = string
}

variable "resource_group_id" {
  description = "Resource group ID for the service and custom role."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "sku_name" {
  description = "Reviewed Web PubSub SKU supporting private endpoints."
  type        = string
}

variable "subnet_id" {
  description = "Private endpoint subnet ID."
  type        = string
}

variable "virtual_network_id" {
  description = "VNet to link to private DNS."
  type        = string
}

variable "app_principal_id" {
  description = "Principal ID of the app workload identity."
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
