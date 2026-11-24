terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

# Free tier does not support network ACLs. Paid tiers receive the request
# restrictions in the initial ARM request; AzureRM manages them afterward.
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
    properties = merge({
      disableAadAuth      = false
      disableLocalAuth    = true
      publicNetworkAccess = "Enabled"
      }, var.sku_name == "Free_F1" ? {} : {
      networkACLs = {
        defaultAction = "Allow"
        publicNetwork = {
          deny = ["ServerConnection", "Trace"]
        }
      }
    })
  }

  response_export_values = ["properties.hostName"]

  lifecycle {
    ignore_changes = [body.properties.networkACLs]
  }
}

resource "azurerm_web_pubsub_network_acl" "this" {
  count          = var.sku_name == "Free_F1" ? 0 : 1
  web_pubsub_id  = azapi_resource.this.id
  default_action = "Allow"

  public_network {
    denied_request_types = ["ServerConnection", "Trace"]
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
