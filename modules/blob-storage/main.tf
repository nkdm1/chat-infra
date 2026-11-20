resource "azurerm_storage_account" "this" {
  name                     = var.name
  resource_group_name      = var.rg-name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = local.tags
}

resource "azurerm_storage_container" "this" {
  name                  = "${var.name}container"
  storage_account_id    = azurerm_storage_account.this.id
}
