resource "azurerm_cosmosdb_account" "this" {
  name                = var.account_name
  location            = var.location
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  free_tier_enabled                = var.free_tier_enabled
  multiple_write_locations_enabled = false
  public_network_access_enabled    = true

  consistency_policy {
    consistency_level = "Session"
  }

  # Single region avoids the additional cost of replicated regions.
  geo_location {
    location          = var.location
    failover_priority = 0
  }

  tags = local.tags
}
