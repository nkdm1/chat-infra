output "id" {
  value       = azurerm_email_communication_service.this.id
  description = "Resource ID of the Email Communication Service."
}

output "communication_service_id" {
  value       = azurerm_communication_service.this.id
  description = "Resource ID of the linked Communication Service."
}

output "endpoint" {
  value       = "https://${azurerm_communication_service.this.hostname}"
  description = "Communication Service HTTPS endpoint."
}

output "sender_address" {
  value       = "donotreply@${azurerm_email_communication_service_domain.this.from_sender_domain}"
  description = "Default sender address for the Azure-managed domain."
}
