variable "name" {
  type        = string
  description = "name of the resource group"
  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "var.name must not be empty."
  }
}

variable "location" {
  type        = string
  description = "azure region for the resource group"
  default     = "polandcentral"
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
  type = map(string)
  default = {}
}

locals {
  tags = merge(var.tags, {
    env = var.env
  })
}
