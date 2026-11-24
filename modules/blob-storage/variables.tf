variable "name" {
  description = "Globally unique name of the storage account"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "The name must be 3–24 lowercase letters and numbers."
  }
}

variable "rg-name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Location of the resource"
  type        = string
}

variable "app_principal_id" {
  description = "Principal ID of the application workload identity."
  type        = string
}

variable "env" {
  type    = string
  default = ""

  validation {
    condition     = length(trimspace(var.env)) > 0
    error_message = "var.env must not be empty"
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  tags = merge(var.tags, {
    env = var.env
  })
}
