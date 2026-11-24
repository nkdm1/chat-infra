output "id" {
  description = "Web PubSub resource ID."
  value       = azapi_resource.this.id
}

output "endpoint" {
  description = "Public HTTPS service endpoint, protected by Entra authentication."
  value       = "https://${azapi_resource.this.output.properties.hostName}"
}
