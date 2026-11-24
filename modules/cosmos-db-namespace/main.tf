resource "azurerm_cosmosdb_sql_database" "this" {
  name                = var.database_name
  resource_group_name = var.resource_group_name
  account_name        = var.account_name
  throughput          = var.throughput
}

resource "azurerm_cosmosdb_sql_container" "this" {
  name                = var.container_name
  resource_group_name = var.resource_group_name
  account_name        = var.account_name
  database_name       = azurerm_cosmosdb_sql_database.this.name

  partition_key_paths = ["/conversationId"]
}

resource "azurerm_cosmosdb_sql_role_assignment" "this" {
  count = var.app_principal_id == null ? 0 : 1

  resource_group_name = var.resource_group_name
  account_name        = var.account_name
  principal_id        = var.app_principal_id
  role_definition_id  = "${var.account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  scope               = "${var.account_id}/dbs/${azurerm_cosmosdb_sql_database.this.name}"
}
