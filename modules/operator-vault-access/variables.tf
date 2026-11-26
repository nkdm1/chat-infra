variable "key_vault_id" {
  description = "Resource ID of the operator-only Key Vault."
  type        = string
}

variable "operator_principal_id" {
  description = "Principal ID of the temporary operator VM managed identity."
  type        = string
}
