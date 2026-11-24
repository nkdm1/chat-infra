output "aks_subnet_id" {
  description = "Resource ID of the existing subnet intended for AKS nodes."
  value       = azurerm_subnet.aks.id
}

output "private_endpoint_subnet_id" {
  description = "Resource ID of the subnet reserved for future private endpoints."
  value       = azurerm_subnet.private_endpoints.id
}

output "postgresql_subnet_id" {
  description = "Resource ID of the delegated PostgreSQL subnet."
  value       = azurerm_subnet.postgresql.id
}

output "egress_public_ip_id" {
  description = "Resource ID of the static AKS outbound IP."
  value       = azurerm_public_ip.egress.id
}

output "egress_public_ip" {
  description = "Static AKS outbound IP, retained with the network stack."
  value       = azurerm_public_ip.egress.ip_address
}

output "gateway_public_ip_id" {
  description = "Resource ID of the static public Gateway IP."
  value       = azurerm_public_ip.gateway.id
}

output "gateway_public_ip" {
  description = "Static public Gateway IP."
  value       = azurerm_public_ip.gateway.ip_address
}

output "gateway_public_ip_name" {
  description = "Name of the static public Gateway IP."
  value       = azurerm_public_ip.gateway.name
}

output "virtual_network_id" {
  description = "Resource ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}
