resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.rg-name
  location            = var.location
  # Anonymous pull is unavailable on Basic; do not enable it if the SKU changes.
  sku                           = "Basic"
  admin_enabled                 = false
  public_network_access_enabled = true

  tags = local.tags
}
