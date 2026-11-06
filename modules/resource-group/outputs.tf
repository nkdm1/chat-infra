output "id" {
  description = "ID of the Azure resource group."
  value       = azurerm_resource_group.this.id
}

output "name" {
  description = "Name of the Azure resource group."
  value       = azurerm_resource_group.this.name
}
