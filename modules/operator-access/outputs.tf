output "virtual_machine_id" {
  value = azurerm_linux_virtual_machine.operator.id
}

output "virtual_machine_name" {
  value = azurerm_linux_virtual_machine.operator.name
}

output "bastion_name" {
  value = try(azurerm_bastion_host.developer[0].name, null)
}

output "principal_id" {
  value = azurerm_linux_virtual_machine.operator.identity[0].principal_id
}
