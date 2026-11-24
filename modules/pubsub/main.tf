terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

# Create the service with its public request restrictions in the initial ARM
# request. The AzureRM ACL resource below manages the ACL after creation.
resource "azapi_resource" "this" {
  type      = "Microsoft.SignalRService/webPubSub@2024-03-01"
  name      = var.name
  parent_id = var.resource_group_id
  location  = var.location
  tags      = local.tags

  body = {
    sku = {
      name     = var.sku_name
      capacity = 1
    }
    properties = {
      disableAadAuth      = false
      disableLocalAuth    = true
      publicNetworkAccess = "Enabled"
      networkACLs = {
        defaultAction = "Allow"
        publicNetwork = {
          deny = ["RESTAPI", "ServerConnection", "Trace"]
        }
      }
    }
  }

  response_export_values = ["properties.hostName"]

  lifecycle {
    ignore_changes = [body.properties.networkACLs]
  }
}

resource "azurerm_private_dns_zone" "this" {
  name                = "privatelink.webpubsub.azure.com"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                 = "${var.name}-vnet-link"
  private_dns_zone_id  = azurerm_private_dns_zone.this.id
  virtual_network_id   = var.virtual_network_id
  registration_enabled = false
  tags                 = local.tags
}

resource "azurerm_private_endpoint" "this" {
  name                = "${var.name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "${var.name}-connection"
    private_connection_resource_id = azapi_resource.this.id
    subresource_names              = ["webpubsub"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this.id]
  }

  tags = local.tags
}

resource "azurerm_web_pubsub_network_acl" "this" {
  web_pubsub_id  = azapi_resource.this.id
  default_action = "Allow"

  public_network {
    denied_request_types = ["RESTAPI", "ServerConnection", "Trace"]
  }

  private_endpoint {
    id                   = azurerm_private_endpoint.this.id
    denied_request_types = ["ClientConnection", "ServerConnection", "Trace"]
  }
}

resource "azurerm_role_definition" "app" {
  name        = "${var.name}-app-data"
  scope       = var.resource_group_id
  description = "Web PubSub token issuance, user delivery and connection management for the chat app."

  permissions {
    data_actions = [
      "Microsoft.SignalRService/WebPubSub/clientConnection/generateToken/action",
      "Microsoft.SignalRService/WebPubSub/clientConnection/write",
      "Microsoft.SignalRService/WebPubSub/user/send/action",
      "Microsoft.SignalRService/WebPubSub/user/read",
    ]
  }

  assignable_scopes = [var.resource_group_id]
}

resource "azurerm_role_assignment" "app" {
  scope              = azapi_resource.this.id
  role_definition_id = azurerm_role_definition.app.role_definition_resource_id
  principal_id       = var.app_principal_id
}
