output "resource_group_name" {
  description = "Created resource group name."
  value       = azurerm_resource_group.this.name
}

output "vnet_name" {
  description = "Created virtual network name."
  value       = azurerm_virtual_network.this.name
}

output "subnet_id" {
  description = "Created subnet ID."
  value       = azurerm_subnet.this.id
}

output "nsg_id" {
  description = "Created NSG ID."
  value       = azurerm_network_security_group.this.id
}
