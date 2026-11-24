variable "name" {
  description = "Globally unique Web PubSub service name."
  type        = string
}

variable "resource_group_id" {
  description = "Resource group ID for the service and custom role."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "sku_name" {
  description = "Web PubSub SKU."
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
