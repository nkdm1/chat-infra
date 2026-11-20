resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.rg-name
  location            = var.location
  sku                 = "Basic"

  tags = local.tags
}
