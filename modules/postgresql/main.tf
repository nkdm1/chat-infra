resource "azurerm_private_dns_zone" "this" {
  name                = var.private_dns_zone_name
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

resource "azurerm_private_dns_zone_virtual_network_link" "additional" {
  for_each = var.additional_virtual_network_ids

  name                 = "${var.name}-${each.key}-vnet-link"
  private_dns_zone_id  = azurerm_private_dns_zone.this.id
  virtual_network_id   = each.value
  registration_enabled = false
  tags                 = local.tags
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                              = var.name
  resource_group_name               = var.resource_group_name
  location                          = var.location
  version                           = var.postgresql_version
  delegated_subnet_id               = var.delegated_subnet_id
  private_dns_zone_id               = azurerm_private_dns_zone.this.id
  public_network_access_enabled     = false
  administrator_login               = var.administrator_login
  administrator_password_wo         = var.administrator_password
  administrator_password_wo_version = var.administrator_password_version
  sku_name                          = var.sku_name
  storage_mb                        = var.storage_mb
  backup_retention_days             = var.backup_retention_days
  geo_redundant_backup_enabled      = false
  tags                              = local.tags

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.this,
    azurerm_private_dns_zone_virtual_network_link.additional,
  ]
}

resource "azurerm_postgresql_flexible_server_configuration" "tls" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = "on"
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  name      = "chat"
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
