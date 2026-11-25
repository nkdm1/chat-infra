# Temporary broad secret-management permission, deliberately scoped to one vault.
resource "azurerm_role_assignment" "secrets_officer" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.operator_principal_id
}
