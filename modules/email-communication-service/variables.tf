variable "name" {
  type        = string
  description = "name of the email communication service"
  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "var.name must not be empty."
  }
}

variable "data_location" {
  type        = string
  description = "region where the data is stored at rest"
  default     = "Europe"
}

variable "resource_group_name" {
  type        = string
  description = "name of the resource group used for this service"
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
