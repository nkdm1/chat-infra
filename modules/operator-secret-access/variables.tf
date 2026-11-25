variable "key_vault_id" {
  description = "Resource ID of the dev application Key Vault."
  type        = string
}

variable "operator_principal_id" {
  description = "Principal ID of the temporary operator VM's managed identity."
  type        = string
}
