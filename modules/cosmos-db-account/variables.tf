variable "account_name" {
  type        = string
  description = "Globally unique Cosmos DB account name (3-44 lowercase letters, digits, or hyphens)."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,42}[a-z0-9]$", var.account_name))
    error_message = "account_name must be 3-44 characters, use lowercase letters, digits, or hyphens, and start/end with a letter or digit."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the shared Cosmos DB account."
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group containing the shared Cosmos DB account."
}

variable "free_tier_enabled" {
  type        = bool
  description = "Enable Cosmos DB free tier. Only one account per subscription can use it."
  default     = true
}

variable "env" {
  type        = string
  description = "Environment tag for this shared resource."

  validation {
    condition     = length(trimspace(var.env)) > 0
    error_message = "env must not be empty."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional resource tags."
  default     = {}
}

locals {
  tags = merge(var.tags, { env = var.env })
}
