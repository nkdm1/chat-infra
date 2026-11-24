variable "name" {
  description = "Globally unique Key Vault name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the vault."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "app_principal_id" {
  description = "Principal ID of the application workload identity."
  type        = string
}

variable "soft_delete_retention_days" {
  description = "Immutable soft-delete retention period in days."
  type        = number

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90 && floor(var.soft_delete_retention_days) == var.soft_delete_retention_days
    error_message = "Key Vault retention must be a whole number between 7 and 90 days."
  }
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
