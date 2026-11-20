output "id" {
  value       = azurerm_cosmosdb_account.this.id
  description = "Resource ID of the shared Cosmos DB account."
}

output "name" {
  value       = azurerm_cosmosdb_account.this.name
  description = "Name of the shared Cosmos DB account."
}

output "resource_group_name" {
  value       = var.resource_group_name
  description = "Resource group containing the shared Cosmos DB account and environment databases."
}

output "endpoint" {
  value       = azurerm_cosmosdb_account.this.endpoint
  description = "Endpoint for applications to connect to the shared Cosmos DB account."
}
