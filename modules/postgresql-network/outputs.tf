output "virtual_network_id" {
  description = "Resource ID of the PostgreSQL virtual network."
  value       = azurerm_virtual_network.this.id
}

output "postgresql_subnet_id" {
  description = "Resource ID of the delegated PostgreSQL subnet."
  value       = azurerm_subnet.postgresql.id
}
