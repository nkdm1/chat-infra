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

resource "azurerm_private_endpoint" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "${var.name}-connection"
    private_connection_resource_id = var.target_resource_id
    subresource_names              = [var.subresource_name]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this.id]
  }

  tags = local.tags
}
