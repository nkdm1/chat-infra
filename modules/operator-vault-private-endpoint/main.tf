resource "azurerm_private_endpoint" "operator_vault" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = merge(var.tags, { env = var.env })

  private_service_connection {
    name                           = "${var.name}-connection"
    private_connection_resource_id = var.vault_id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}
