resource "azurerm_role_assignment" "operator_secrets_reader" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.operator_principal_id
}
