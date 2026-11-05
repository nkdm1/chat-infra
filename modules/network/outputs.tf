output "aks_subnet_id" {
  description = "Resource ID of the existing subnet intended for AKS nodes."
  value       = azurerm_subnet.aks.id
}

output "private_endpoint_subnet_id" {
  description = "Resource ID of the subnet reserved for future private endpoints."
  value       = azurerm_subnet.private_endpoints.id
}

output "virtual_network_id" {
  description = "Resource ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}
