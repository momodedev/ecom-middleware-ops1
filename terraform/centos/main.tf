data "azurerm_resource_group" "existing" {
  count = var.use_existing_foundation ? 1 : 0
  name  = var.resource_group_name
}

resource "azurerm_resource_group" "this" {
  count    = var.use_existing_foundation ? 0 : 1
  name     = var.resource_group_name
  location = var.location
}

data "azurerm_virtual_network" "existing" {
  count               = var.use_existing_foundation ? 1 : 0
  name                = var.vnet_name
  resource_group_name = local.foundation_rg_name
}

resource "azurerm_virtual_network" "this" {
  count               = var.use_existing_foundation ? 0 : 1
  name                = var.vnet_name
  location            = local.foundation_rg_location
  resource_group_name = local.foundation_rg_name
  address_space       = var.vnet_address_space
}

data "azurerm_subnet" "existing" {
  count                = var.use_existing_foundation ? 1 : 0
  name                 = var.subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = local.foundation_rg_name
}

resource "azurerm_subnet" "this" {
  count                = var.use_existing_foundation ? 0 : 1
  name                 = var.subnet_name
  resource_group_name  = local.foundation_rg_name
  virtual_network_name = var.vnet_name
  address_prefixes     = var.subnet_address_prefixes

  default_outbound_access_enabled           = false
  private_endpoint_network_policies         = "Disabled"
  private_link_service_network_policies_enabled = true
}

data "azurerm_network_security_group" "existing" {
  count               = var.use_existing_foundation ? 1 : 0
  name                = var.nsg_name
  resource_group_name = local.foundation_rg_name
}

resource "azurerm_network_security_group" "this" {
  count               = var.use_existing_foundation ? 0 : 1
  name                = var.nsg_name
  location            = local.foundation_rg_location
  resource_group_name = local.foundation_rg_name
}

locals {
  foundation_rg_name     = var.use_existing_foundation ? data.azurerm_resource_group.existing[0].name : azurerm_resource_group.this[0].name
  foundation_rg_location = var.use_existing_foundation ? data.azurerm_resource_group.existing[0].location : azurerm_resource_group.this[0].location

  foundation_vnet_name = var.use_existing_foundation ? data.azurerm_virtual_network.existing[0].name : azurerm_virtual_network.this[0].name
  foundation_subnet_id = var.use_existing_foundation ? data.azurerm_subnet.existing[0].id : azurerm_subnet.this[0].id

  foundation_nsg_name = var.use_existing_foundation ? data.azurerm_network_security_group.existing[0].name : azurerm_network_security_group.this[0].name
  foundation_nsg_id   = var.use_existing_foundation ? data.azurerm_network_security_group.existing[0].id : azurerm_network_security_group.this[0].id
}

resource "azurerm_network_security_rule" "grafana_3000" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "allow-grafana-3000"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3000"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "prometheus_9090" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "allow-prometheus-9090"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "9090"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "kafka_external_9094" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "allow-kafka-external-9094"
  priority                    = 130
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "9094"
  source_address_prefix       = var.allowed_cidr
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "kafka_exporter_9308" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "allow-kafka-exporter-9308"
  priority                    = 140
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "9308"
  source_address_prefix       = var.allowed_cidr
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "node_exporter_9100" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "allow-node-exporter-9100"
  priority                    = 150
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "9100"
  source_address_prefix       = var.allowed_cidr
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "control_ssh" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "control-ssh-${var.control_ssh_port}"
  priority                    = 3100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.control_ssh_port)
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "ssh_22" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "allow-ssh-22"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "kafka_client_9092" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "allow-kafka-client-9092"
  priority                    = 160
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "9092"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "zookeeper_2181" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "allow-zookeeper-2181"
  priority                    = 170
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "2181"
  source_address_prefix       = var.allowed_cidr
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_subnet_network_security_group_association" "this" {
  count                     = var.manage_subnet_nsg_association ? 1 : 0
  subnet_id                 = local.foundation_subnet_id
  network_security_group_id = local.foundation_nsg_id
}
