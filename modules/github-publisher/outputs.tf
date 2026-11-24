output "client_id" {
  description = "Publisher managed identity client ID for GitHub OIDC."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "tenant_id" {
  description = "Azure tenant ID for GitHub OIDC."
  value       = data.azurerm_client_config.current.tenant_id
}

output "principal_id" {
  description = "Publisher managed identity principal ID."
  value       = azurerm_user_assigned_identity.this.principal_id
}
