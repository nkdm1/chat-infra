variable "name" {
  description = "Name of the Azure Managed Redis instance."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing Redis."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "sku_name" {
  description = "Reviewed Azure Managed Redis SKU."
  type        = string
}

variable "high_availability_enabled" {
  description = "Whether to enable Redis high availability."
  type        = bool
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
