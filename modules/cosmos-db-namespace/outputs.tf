output "account_endpoint" {
  value       = var.endpoint
  description = "Endpoint for the environment's Cosmos DB database."
}

output "database_name" {
  value       = azurerm_cosmosdb_sql_database.this.name
  description = "Environment-specific Cosmos DB database name."
}

output "container_name" {
  value       = azurerm_cosmosdb_sql_container.this.name
  description = "Messages container name."
}
