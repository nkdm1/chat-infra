output "id" {
  description = "Resource ID of the application identity."
  value       = azurerm_user_assigned_identity.this.id
}

output "principal_id" {
  description = "Principal ID used for resource role assignments."
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "client_id" {
  description = "Client ID used by the Kubernetes service account."
  value       = azurerm_user_assigned_identity.this.client_id
}
