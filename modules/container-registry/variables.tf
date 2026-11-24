variable "name" {
  description = "Name of the container registry"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.name))
    error_message = "Container registry name must be 5–50 alphanumeric characters."
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
