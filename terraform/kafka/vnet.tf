############### RG #################
data azurerm_subscription "current" { }

# Reuse existing RG when told to; otherwise create
data "azurerm_resource_group" "existing" {
  count = var.use_existing_kafka_network ? 1 : 0
  name  = var.resource_group_name
}

resource "azurerm_resource_group" "example" {
  count    = var.use_existing_kafka_network ? 0 : 1
  location = var.resource_group_location
  name     = var.resource_group_name
}

resource "azurerm_virtual_network" "kafka" {
  count               = var.use_existing_kafka_network ? 0 : 1
  name                = var.kafka_vnet_name
  resource_group_name = local.kafka_rg_name
  location            = local.kafka_rg_location
  address_space       = ["172.16.0.0/16"]
}

data "azurerm_virtual_network" "kafka" {
  count               = var.use_existing_kafka_network ? 1 : 0
  name                = var.kafka_vnet_name
  resource_group_name = var.existing_kafka_vnet_resource_group_name != "" ? var.existing_kafka_vnet_resource_group_name : var.resource_group_name
}

resource "azurerm_subnet" "kafka" {
  count                = var.use_existing_kafka_network ? 0 : 1
  name                 = var.kafka_subnet_name
  resource_group_name  = local.kafka_rg_name
  virtual_network_name = azurerm_virtual_network.kafka[0].name
  address_prefixes     = ["172.16.1.0/24"]
}

data "azurerm_subnet" "kafka" {
  count                = var.use_existing_kafka_network ? 1 : 0
  name                 = var.kafka_subnet_name
  virtual_network_name = var.kafka_vnet_name
  resource_group_name  = var.existing_kafka_vnet_resource_group_name != "" ? var.existing_kafka_vnet_resource_group_name : var.resource_group_name
}

locals {
  kafka_rg_name      = var.use_existing_kafka_network ? data.azurerm_resource_group.existing[0].name : azurerm_resource_group.example[0].name
  kafka_rg_location  = var.use_existing_kafka_network ? data.azurerm_resource_group.existing[0].location : azurerm_resource_group.example[0].location
  kafka_network_rg   = var.existing_kafka_vnet_resource_group_name != "" ? var.existing_kafka_vnet_resource_group_name : var.resource_group_name
  kafka_vnet_id      = var.use_existing_kafka_network ? data.azurerm_virtual_network.kafka[0].id : azurerm_virtual_network.kafka[0].id
  kafka_subnet_id    = var.use_existing_kafka_network ? data.azurerm_subnet.kafka[0].id : azurerm_subnet.kafka[0].id
  kafka_nsg_id       = var.kafka_nsg_id != "" ? var.kafka_nsg_id : (!var.use_existing_kafka_network ? azurerm_network_security_group.example[0].id : null)
  attach_kafka_nsg   = var.kafka_nsg_id != "" || (!var.use_existing_kafka_network)
}

resource "azurerm_network_security_group" "example" {
  count               = var.kafka_nsg_id != "" || var.use_existing_kafka_network ? 0 : 1
  name                = var.kafka_nsg_name
  location            = local.kafka_rg_location
  resource_group_name = local.kafka_rg_name

  # SSH only from control node VNet
  security_rule {
    name                       = "ssh-from-control"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "172.17.0.0/16"  # Control VNet only
    destination_address_prefix = "*"
  }

  # Kafka client port - internal cluster communication + control node access
  security_rule {
    name                       = "kafka-client"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9092"
    source_address_prefixes    = ["172.16.0.0/16", "172.17.0.0/16"]  # Kafka + Control VNets
    destination_address_prefix = "*"
  }

  # Kafka controller - internal cluster only
  security_rule {
    name                       = "kafka-controller"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9093"
    source_address_prefixes    = ["172.16.0.0/16", "172.17.0.0/16"]  # Kafka + Control VNets
    destination_address_prefix = "*"
  }

  # Kafka external listener - internal only
  security_rule {
    name                       = "kafka-external"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9094"
    source_address_prefixes    = ["172.16.0.0/16", "172.17.0.0/16"]  # Kafka + Control VNets
    destination_address_prefix = "*"
  }

  # Kafka exporter - monitoring from control node
  security_rule {
    name                       = "kafka-exporter"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9308"
    source_address_prefixes    = ["172.16.0.0/16", "172.17.0.0/16"]  # Kafka + Control VNets
    destination_address_prefix = "*"
  }

  # Node exporter - monitoring from control node
  security_rule {
    name                       = "node-exporter"
    priority                   = 150
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9100"
    source_address_prefixes    = ["172.16.0.0/16", "172.17.0.0/16"]  # Kafka + Control VNets
    destination_address_prefix = "*"
  }

  # Deny all other inbound traffic explicitly
  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Environment = "production"
    Component   = "kafka"
    Security    = "private-only"
  }
}

resource "azurerm_subnet_network_security_group_association" "example" {
  count                     = var.use_existing_kafka_network || var.kafka_nsg_id != "" ? 0 : 1
  subnet_id                 = azurerm_subnet.kafka[0].id
  network_security_group_id = azurerm_network_security_group.example[0].id
}

# Data source to reference the existing control VNet
data "azurerm_virtual_network" "control" {
  count               = var.enable_vnet_peering ? 1 : 0
  name                = var.control_vnet_name
  resource_group_name = var.control_resource_group_name
}

# VNet peering: Kafka to Control
resource "azurerm_virtual_network_peering" "kafka_to_control" {
  count                        = var.enable_vnet_peering ? 1 : 0
  name                         = "kafka-to-control-peer"
  resource_group_name          = local.kafka_network_rg
  virtual_network_name         = var.kafka_vnet_name
  remote_virtual_network_id    = data.azurerm_virtual_network.control[0].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# VNet peering: Control to Kafka
resource "azurerm_virtual_network_peering" "control_to_kafka" {
  count                        = var.enable_vnet_peering ? 1 : 0
  name                         = "control-to-kafka-peer"
  resource_group_name          = var.control_resource_group_name
  virtual_network_name         = var.control_vnet_name
  remote_virtual_network_id    = local.kafka_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# ==================== NAT Gateway Configuration ====================
# NAT Gateway provides OUTBOUND internet access for Kafka brokers
# This allows VMs to download packages, updates, etc. without public IPs
# Inbound access is NOT possible through NAT - brokers remain private

resource "azurerm_public_ip" "example" {
  count               = var.enable_kafka_nat_gateway ? 1 : 0
  name                = var.kafka_nat_ip_name
  location            = local.kafka_rg_location
  resource_group_name = local.kafka_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = {
    Environment = "production"
    Component   = "nat-gateway"
    Purpose     = "outbound-only"
  }
}

resource "azurerm_nat_gateway" "example" {
  count                  = var.enable_kafka_nat_gateway ? 1 : 0
  name                   = var.kafka_nat_gateway_name
  location               = local.kafka_rg_location
  resource_group_name    = local.kafka_rg_name
  sku_name               = "Standard"
  idle_timeout_in_minutes = 10
  
  tags = {
    Environment = "production"
    Component   = "nat-gateway"
    Purpose     = "outbound-internet-access"
  }
}

resource "azurerm_nat_gateway_public_ip_association" "example" {
  count               = var.enable_kafka_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.example[0].id
  public_ip_address_id = azurerm_public_ip.example[0].id
}

resource "azurerm_subnet_nat_gateway_association" "example" {
  count         = (var.enable_kafka_nat_gateway && !var.use_existing_kafka_network) ? 1 : 0
  subnet_id      = local.kafka_subnet_id
  nat_gateway_id = azurerm_nat_gateway.example[0].id
}
