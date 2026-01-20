############### RG #################
data azurerm_subscription "current" { }
data "azurerm_client_config" "current" {}

# Create RG only if NOT using existing networks; otherwise data-source the existing RG
resource "azurerm_resource_group" "example" {
  count    = var.use_existing_control_network ? 0 : 1
  location = var.resource_group_location
  name     = var.resource_group_name
}

data "azurerm_resource_group" "example" {
  count = var.use_existing_control_network ? 1 : 0
  name  = var.resource_group_name
}

locals {
  resource_group_name  = var.use_existing_control_network ? data.azurerm_resource_group.example[0].name : azurerm_resource_group.example[0].name
  resource_group_id    = var.use_existing_control_network ? data.azurerm_resource_group.example[0].id : azurerm_resource_group.example[0].id
  resource_group_location = var.use_existing_control_network ? data.azurerm_resource_group.example[0].location : azurerm_resource_group.example[0].location
}

resource "azurerm_virtual_network" "control" {
  count               = var.use_existing_control_network ? 0 : 1
  name                = var.control_vnet_name
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  address_space       = ["172.17.0.0/16"]
}

data "azurerm_virtual_network" "control" {
  count               = var.use_existing_control_network ? 1 : 0
  name                = var.control_vnet_name
  resource_group_name = var.control_network_resource_group_name != "" ? var.control_network_resource_group_name : var.resource_group_name
}

resource "azurerm_subnet" "control" {
  count                        = var.use_existing_control_network ? 0 : 1
  name                         = var.control_subnet_name
  resource_group_name          = local.resource_group_name
  virtual_network_name         = azurerm_virtual_network.control[0].name
  address_prefixes             = ["172.17.1.0/24"]
  service_endpoints            = ["Microsoft.KeyVault"]
  default_outbound_access_enabled = false
}

data "azurerm_subnet" "control" {
  count                = var.use_existing_control_network ? 1 : 0
  name                 = var.control_subnet_name
  virtual_network_name = var.control_vnet_name
  resource_group_name  = var.control_network_resource_group_name != "" ? var.control_network_resource_group_name : var.resource_group_name
}

locals {
  control_subnet_id = var.use_existing_control_network ? data.azurerm_subnet.control[0].id : azurerm_subnet.control[0].id
}

resource "azurerm_network_security_group" "example" {
  name                = var.control_nsg_name
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

  security_rule {
    name                       = "test123"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "prometheus"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9090"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "grafana"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "example" {
  subnet_id                 = local.control_subnet_id
  network_security_group_id = azurerm_network_security_group.example.id
}

resource "azurerm_public_ip" "control" {
  name                = "control-ip"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "example" {
  name                = "control-nic"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = local.control_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.control.id
  }
}

resource "azurerm_linux_virtual_machine" "example" {
  name                = "control-node"
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  size                = var.control_vm_size
  network_interface_ids = [
    azurerm_network_interface.example.id,
  ]

  computer_name  = "control"
  admin_username = "azureadmin"
  admin_ssh_key {
    username   = "azureadmin"
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  lifecycle {
    ignore_changes = [bypass_platform_safety_checks_on_user_schedule_enabled]
  }
  # provisioner "remote-exec" {
  #   when    = destroy
  #   inline = [
  #     "cd ecom-middleware-ops/terraform/kafka",
  #     "terraform destroy -var-file='sub_id.tfvars' -auto-approve",
  #   ]
  # }
}


resource "azurerm_role_assignment" "control" {
  scope              = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id       = azurerm_linux_virtual_machine.example.identity[0].principal_id
}


resource "azurerm_role_assignment" "user" {
  count                = var.deploy_mode != "separate" ? 1 : 0
  scope                = azurerm_key_vault.example[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}


resource "null_resource" "deploy_private_vms"{
  # Deploys Kafka broker VMs (individual VMs, not VMSS)
  # Only executes when deploy_mode is set to "together"
  count = var.deploy_mode == "together" ? 1 : 0
  
  triggers = { 
    always_run = "${timestamp()}"
  }
  connection {
    type = "ssh"
    host = azurerm_linux_virtual_machine.example.public_ip_address
    user = "azureadmin"
    private_key = file(pathexpand(var.ssh_private_key_path))
  }
  provisioner "remote-exec" {
    inline = [
      "KAFKA_VM_ZONE=${var.kafka_vm_zone} ENABLE_AVAILABILITY_ZONES=${var.enable_availability_zones} USE_EXISTING_KAFKA_NETWORK=${var.use_existing_kafka_network} EXISTING_KAFKA_VNET_RESOURCE_GROUP_NAME=${var.existing_kafka_vnet_resource_group_name} KAFKA_VNET_NAME=${var.kafka_vnet_name} KAFKA_SUBNET_NAME=${var.kafka_subnet_name} ENABLE_KAFKA_NAT_GATEWAY=${var.enable_kafka_nat_gateway} KAFKA_NSG_ID=${var.kafka_nsg_id} ./private_vms_deploy.sh ${var.ARM_SUBSCRIPTION_ID} ${var.tf_cmd_type} ${var.kafka_instance_count} ${var.kafka_data_disk_iops} ${var.kafka_data_disk_throughput_mbps} ${var.kafka_vm_size} ${var.ansible_run_id} ${var.kafka_resource_group_name} ${var.resource_group_location}",
    ]
  }
  depends_on = [null_resource.Init_private_vms]
}



resource "null_resource" "Init_private_vms"{
  # Initialize control node for Kafka VM deployment (individual VMs, not VMSS)
  # Skip this provisioner when deploy_mode="separate" (control-only mode)
  count = var.deploy_mode != "separate" ? 1 : 0
  
  triggers = { 
    trigger = join(",", azurerm_linux_virtual_machine.example.public_ip_addresses) 
  }
  connection {
    type = "ssh"
    host = azurerm_linux_virtual_machine.example.public_ip_address
    user = "azureadmin"
    private_key = file(pathexpand(var.ssh_private_key_path))
  }
  provisioner "remote-exec" {
    inline = [
      "chmod +x private_vms_init.sh",
      "chmod +x private_vms_deploy.sh",
      "./private_vms_init.sh",
    ]
  }
  depends_on = [azurerm_role_assignment.control, azurerm_linux_virtual_machine.example]
}

# resource "azurerm_virtual_machine_extension" "example" {
#   name                 = "hostname"
#   virtual_machine_id   = azurerm_linux_virtual_machine.example.id
#   publisher            = "Microsoft.Azure.Extensions"
#   type                 = "CustomScript"
#   type_handler_version = "2.0"

#   protected_settings = <<PROT
#   {
#       "script": "${base64encode(templatefile("private_vms_init.sh", { sub_id=var.ARM_SUBSCRIPTION_ID }))}"
#   }
#   PROT

#   depends_on = [azurerm_role_assignment.control, azurerm_role_assignment.keyvault, azurerm_key_vault_secret.example]
# }