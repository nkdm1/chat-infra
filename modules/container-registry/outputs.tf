output "id" {
  value       = azurerm_container_registry.this.id
  description = "ID of the container registry"
}

output "login_server" {
  value       = azurerm_container_registry.this.login_server
  description = "Login server of the container registry"
}
