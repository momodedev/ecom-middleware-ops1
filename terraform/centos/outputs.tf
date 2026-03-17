output "resource_group_name" {
  description = "Created resource group name."
  value       = local.foundation_rg_name
}

output "vnet_name" {
  description = "Created virtual network name."
  value       = local.foundation_vnet_name
}

output "subnet_id" {
  description = "Created subnet ID."
  value       = local.foundation_subnet_id
}

output "nsg_id" {
  description = "Created NSG ID."
  value       = local.foundation_nsg_id
}

output "kafka_broker_public_ips" {
  description = "Public IP addresses of CentOS Kafka brokers (populated when is_public=true)."
  value       = var.is_public ? azurerm_public_ip.brokers[*].ip_address : []
}

output "kafka_broker_private_ips" {
  description = "Private IP addresses of CentOS Kafka brokers."
  value       = azurerm_linux_virtual_machine.brokers[*].private_ip_address
}
