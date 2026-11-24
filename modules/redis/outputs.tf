output "id" {
  description = "Resource ID of the Azure Managed Redis instance."
  value       = azurerm_managed_redis.this.id
}

output "hostname" {
  description = "Redis hostname; resolve through private DNS."
  value       = azurerm_managed_redis.this.hostname
}

output "port" {
  description = "TLS database port."
  value       = azurerm_managed_redis.this.default_database[0].port
}
