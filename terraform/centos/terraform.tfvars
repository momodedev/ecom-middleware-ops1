# ── Azure subscription ──────────────────────────────────────────────────────
subscription_id = "8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b"

# ── Networking (already deployed, must match existing state) ─────────────────
location            = "westus"
resource_group_name = "kafka-perf-v5-centos"
vnet_name           = "rds-prod-vnet"
subnet_name         = "rds-prod-subnet"
nsg_name            = "rds-prod-nsg"
use_existing_foundation = true
manage_network_security_rules = false

vnet_address_space      = ["10.20.0.0/16"]
subnet_address_prefixes = ["10.20.1.0/24"]

allowed_cidr     = "10.20.0.0/16"
control_ssh_port = 6666

# ── Kafka broker VMs (CentOS 7.9, Azure V5, OpenJDK 11) ─────────────────────
kafka_instance_count    = 3
kafka_vm_size           = "Standard_D8s_v5"
enable_availability_zones = true
kafka_vm_zone           = "1"
kafka_admin_username    = "centosmadmin"
kafka_data_disk_size_gb = 1024
use_premium_v2_disks = true
kafka_data_disk_iops = 3000
kafka_data_disk_throughput_mbps = 125
is_public               = true   # New VNet has no peering to control node – public IPs required
ssh_public_key_path     = "~/.ssh/id_rsa.pub"
ansible_run_id          = ""
enable_ansible_provisioner = true  # Run only when applying from Linux control node (/bin/bash required)

# ── Control node / Ansible paths ─────────────────────────────────────────────
repository_name  = "ecom-middleware-ops1"
control_node_user = "azureadmin"
# ansible_venv_path   = ""   # auto-computed: /home/azureadmin/ansible-venv
# repository_base_dir = ""   # auto-computed: /home/azureadmin/ecom-middleware-ops1
