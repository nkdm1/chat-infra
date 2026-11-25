variable "name" {
  description = "Private endpoint name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the endpoint and private DNS zone."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "subnet_id" {
  description = "Subnet for the private endpoint."
  type        = string
}

variable "virtual_network_id" {
  description = "VNet linked to the private DNS zone."
  type        = string
}

variable "additional_virtual_network_ids" {
  description = "Additional VNets linked to the private DNS zone, keyed by link suffix."
  type        = map(string)
  default     = {}
}

variable "target_resource_id" {
  description = "Resource ID of the private-link service."
  type        = string
}

variable "subresource_name" {
  description = "Private-link group ID."
  type        = string
}

variable "private_dns_zone_name" {
  description = "Service-specific Azure private DNS zone."
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
