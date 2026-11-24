variable "name" {
  description = "Globally unique PostgreSQL Flexible Server name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the server."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "virtual_network_id" {
  description = "VNet linked to the private DNS zone."
  type        = string
}

variable "additional_virtual_network_ids" {
  description = "Additional VNets linked to the PostgreSQL private DNS zone, keyed by link suffix."
  type        = map(string)
  default     = {}
}

variable "delegated_subnet_id" {
  description = "Subnet delegated to PostgreSQL Flexible Server."
  type        = string
}

variable "private_dns_zone_name" {
  description = "Private DNS zone ending in .postgres.database.azure.com."
  type        = string
}

variable "postgresql_version" {
  description = "PostgreSQL major version."
  type        = string
}

variable "sku_name" {
  description = "Reviewed PostgreSQL Flexible Server SKU."
  type        = string
}

variable "storage_mb" {
  description = "Provisioned server storage in MiB."
  type        = number
}

variable "backup_retention_days" {
  description = "Number of days for PostgreSQL backups."
  type        = number
}

variable "administrator_login" {
  description = "Server administrator login; not the application login."
  type        = string
}

variable "administrator_password" {
  description = "Administrator password, supplied securely at runtime and never stored in state."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "administrator_password_version" {
  description = "Increment when rotating the write-only administrator password."
  type        = number
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
