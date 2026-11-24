output "storage_account_id" {
  value       = azurerm_storage_account.this.id
  description = "ID of the storage account"
}

output "blob_endpoint" {
  value       = azurerm_storage_account.this.primary_blob_endpoint
  description = "Blob service endpoint for the application."
}

output "storage_container_id" {
  value       = azurerm_storage_container.this.id
  description = "ID of the storage container"
}

output "storage_container_url" {
  value       = azurerm_storage_container.this.url
  description = "URL of the storage container"
}
