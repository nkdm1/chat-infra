variable "name" {
  description = "Name of the storage account and prefix to container name"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.name))
    error_message = "The name can contain only lowercase letters and numbers."
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

variable "env" {
  type    = string
  default = ""

  validation {
    condition     = length(trimspace(var.env)) > 0
    error_message = "var.env msut not be empty"
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
