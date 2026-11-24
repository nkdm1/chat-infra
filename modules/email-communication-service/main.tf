resource "azurerm_email_communication_service" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  data_location       = var.data_location
  tags                = local.tags
}

resource "azurerm_email_communication_service_domain" "this" {
  name                             = "AzureManagedDomain"
  email_service_id                 = azurerm_email_communication_service.this.id
  domain_management                = "AzureManaged"
  user_engagement_tracking_enabled = false
}

resource "azurerm_communication_service" "this" {
  name                = var.communication_service_name
  resource_group_name = var.resource_group_name
  data_location       = var.data_location
  tags                = local.tags
}

resource "azurerm_communication_service_email_domain_association" "this" {
  communication_service_id = azurerm_communication_service.this.id
  email_service_domain_id  = azurerm_email_communication_service_domain.this.id
}
