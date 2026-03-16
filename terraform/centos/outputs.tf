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

output "kafka_broker_public_ips" {
  description = "Public IP addresses of CentOS Kafka brokers (populated when is_public=true)."
  value       = var.is_public ? azurerm_public_ip.brokers[*].ip_address : []
}

output "kafka_broker_private_ips" {
  description = "Private IP addresses of CentOS Kafka brokers."
  value       = azurerm_linux_virtual_machine.brokers[*].private_ip_address
}
