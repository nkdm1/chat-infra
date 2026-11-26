variable "name" {
  description = "Name of the operator-vault private endpoint."
  type        = string
}

variable "location" {
  description = "Azure region for the private endpoint."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the endpoint."
  type        = string
}

variable "subnet_id" {
  description = "Private-endpoint subnet ID in the dev network."
  type        = string
}

variable "vault_id" {
  description = "Resource ID of the retained operator Key Vault."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID of the existing privatelink.vaultcore.azure.net zone."
  type        = string
}

variable "env" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
