variable "role_name" {
  description = "Name of the temporary custom role."
  type        = string
}

variable "resource_group_id" {
  description = "Resource group in which the role is assignable."
  type        = string
}

variable "redis_resource_id" {
  description = "Resource ID of the target Managed Redis instance."
  type        = string
}

variable "operator_principal_id" {
  description = "Principal ID of the temporary operator VM's managed identity."
  type        = string
}
