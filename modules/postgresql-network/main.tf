resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  tags                = local.tags
}

resource "azurerm_subnet" "postgresql" {
  name                 = var.subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.subnet_address_prefixes

  service_endpoint {
    service = "Microsoft.Storage"
  }

  delegation {
    name = "postgresql"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_virtual_network_peering" "to_app" {
  name                      = "${var.vnet_name}-to-app"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.this.name
  remote_virtual_network_id = var.app_virtual_network_id
}

resource "azurerm_virtual_network_peering" "from_app" {
  name                      = "${var.app_virtual_network_name}-to-postgresql"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = var.app_virtual_network_name
  remote_virtual_network_id = azurerm_virtual_network.this.id

  # Azure does not support concurrent peering updates for the same VNet pair.
  depends_on = [azurerm_virtual_network_peering.to_app]
}
