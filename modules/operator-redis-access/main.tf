# Temporary control-plane permission to retrieve the Redis database access keys.
resource "azurerm_role_definition" "list_keys" {
  name        = var.role_name
  scope       = var.resource_group_id
  description = "Temporary operator access to list keys for the dev Redis database."

  permissions {
    actions = ["Microsoft.Cache/redisEnterprise/databases/listKeys/action"]
  }

  assignable_scopes = [var.resource_group_id]
}

resource "azurerm_role_assignment" "list_keys" {
  scope              = "${var.redis_resource_id}/databases/default"
  role_definition_id = azurerm_role_definition.list_keys.role_definition_resource_id
  principal_id       = var.operator_principal_id
}
