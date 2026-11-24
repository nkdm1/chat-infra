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

# Azure's reported SDK authorization requires control-plane write. This role
# can modify the service; verify actual least-privilege behavior before use.
resource "azurerm_role_definition" "app" {
  name        = "${var.communication_service_name}-app-email"
  scope       = var.resource_group_id
  description = "Communication Service permissions for the email-sending app."

  permissions {
    actions = [
      "Microsoft.Communication/CommunicationServices/read",
      "Microsoft.Communication/CommunicationServices/write",
    ]
  }

  assignable_scopes = [var.resource_group_id]
}

resource "azurerm_role_assignment" "app" {
  scope              = azurerm_communication_service.this.id
  role_definition_id = azurerm_role_definition.app.role_definition_resource_id
  principal_id       = var.app_principal_id
}
