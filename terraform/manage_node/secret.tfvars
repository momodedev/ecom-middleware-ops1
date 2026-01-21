kafka_vnet_name                         = "vnet-t1"   # CHANGE to your existing VNet name
kafka_subnet_name                       = "default" # CHANGE to your existing subnet name
control_vnet_name                       = "vnet-t1"   # same VNet for control + Kafka
control_subnet_name                     = "default" # reuse same subnet for control (or set a dedicated subnet name if it exists)
github_token         = ""
ARM_SUBSCRIPTION_ID  = "8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b" #"8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b"
tf_cmd_type          = "apply"
kafka_instance_count = 3
deploy_mode          = "separate"
kafka_vm_size        = "Standard_D8ls_v6"

# Region
resource_group_location = "westus3"

# Single resource group for both control and Kafka
resource_group_name      = "kafka_t1"
kafka_resource_group_name = "kafka_t1"

# Deploy into an existing VNet/subnet (shared by control + Kafka)
use_existing_control_network             = true
control_network_resource_group_name     = "kafka_t1"   # RG that already has the VNet
use_existing_kafka_network              = true
existing_kafka_vnet_resource_group_name = "kafka_t1"   # same RG as above
#kafka_vnet_name                         = "existing-vnet-name"   # CHANGE to your existing VNet name
#kafka_subnet_name                       = "existing-subnet-name" # CHANGE to your existing subnet name
enable_vnet_peering                     = false                   # same VNet => no peering needed
enable_kafka_nat_gateway                = false                   # assume subnet already has outbound path
is_public_kafka                         = false                   # Set to true to create public IPs for brokers; false = private with NAT
kafka_nsg_id                            = "/subscriptions/8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b/resourceGroups/kafka_t1/providers/Microsoft.Network/networkSecurityGroups/control-nsg"                     # optional: set if you have an NSG to reuse
control_nsg_id                          = "/subscriptions/8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b/resourceGroups/kafka_t1/providers/Microsoft.Network/networkSecurityGroups/control-nsg"                   # use existing NSG for control node

# Availability Zone Configuration
# For regions WITHOUT Availability Zones (westus, northcentralus, etc.):
kafka_vm_zone             = ""
enable_availability_zones = false

# For regions WITH Availability Zones (wwestus3, westus3, eastus, westus3, etc.):
# Uncomment the lines below and comment out the lines above:
# kafka_vm_zone             = "2"
# enable_availability_zones = true

control_vm_size = "Standard_D8ls_v6"
#kafka_data_disk_iops = 600
#kafka_data_disk_throughput_mbps = 200
# ssh_public_key_path  = "~/.ssh/custom_key.pub"
# ssh_private_key_path = "~/.ssh/custom_key"

