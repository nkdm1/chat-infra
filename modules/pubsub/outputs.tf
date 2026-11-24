output "id" {
  description = "Web PubSub resource ID."
  value       = azapi_resource.this.id
}

output "endpoint" {
  description = "HTTPS service endpoint, resolving privately inside the VNet."
  value       = "https://${azapi_resource.this.output.properties.hostName}"
}
