variable "name" {
  description = "Name of the application managed identity."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the identity."
  type        = string
}

variable "location" {
  description = "Azure region."
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
