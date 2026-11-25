variable "name" {
  description = "Name of the temporary operator VM."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "virtual_network_id" {
  type = string
}

variable "virtual_network_name" {
  type = string
}

variable "subnet_name" {
  type = string
}

variable "subnet_address_prefixes" {
  type = list(string)
}

variable "vm_size" {
  type = string
}

variable "admin_username" {
  type = string
}

variable "ssh_public_key" {
  description = "Temporary operator SSH public key; never provide a private key."
  type        = string

  validation {
    condition     = can(regex("^ssh-rsa [A-Za-z0-9+/=]+", var.ssh_public_key))
    error_message = "ssh_public_key must be an RSA public key in OpenSSH format."
  }
}

variable "env" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  tags = merge(var.tags, { env = var.env })
}
