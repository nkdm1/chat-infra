output "id" {
  description = "Resource ID of the private endpoint."
  value       = azurerm_private_endpoint.this.id
}

output "private_dns_zone_id" {
  description = "Resource ID of the linked private DNS zone."
  value       = azurerm_private_dns_zone.this.id
}
