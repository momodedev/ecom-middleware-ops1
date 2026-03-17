variable "subscription_id" {
  description = "Azure subscription ID used for deployment."
  type        = string
}

variable "location" {
  description = "Azure region for all networking resources."
  type        = string
  default     = "westus"
}

variable "resource_group_name" {
  description = "Resource group name for the CentOS performance test network."
  type        = string
  default     = "kafka-perf-v5-centos"
}

variable "vnet_name" {
  description = "Virtual network name."
  type        = string
  default     = "kafka-perf-v5-centos-vnet"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network."
  type        = list(string)
  default     = ["10.20.0.0/16"]
}

variable "subnet_name" {
  description = "Subnet name inside the VNet."
  type        = string
  default     = "kafka-perf-v5-centos-subnet"
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for the subnet."
  type        = list(string)
  default     = ["10.20.1.0/24"]
}

variable "nsg_name" {
  description = "Network Security Group name for Kafka test traffic."
  type        = string
  default     = "kafka-perf-v5-centos-nsg"
}

variable "allowed_cidr" {
  description = "CIDR allowed to access Kafka-related inbound ports."
  type        = string
  default     = "10.20.0.0/16"
}

variable "control_ssh_port" {
  description = "SSH port used by the control node."
  type        = number
  default     = 6666
}

# ── Kafka broker VM configuration ───────────────────────────────────────────

variable "kafka_instance_count" {
  description = "Number of CentOS 7.9 Kafka broker VMs to provision."
  type        = number
  default     = 3
}

variable "kafka_vm_size" {
  description = "Azure VM SKU for CentOS Kafka brokers (V5 family for perf test lane A)."
  type        = string
  default     = "Standard_D8s_v5"
}

variable "kafka_admin_username" {
  description = "Admin username for CentOS broker VMs (also used as Ansible remote_user)."
  type        = string
  default     = "centosmadmin"
}

variable "kafka_data_disk_size_gb" {
  description = "Size in GiB of the Premium SSD data disk attached to each Kafka broker."
  type        = number
  default     = 256
}

variable "is_public" {
  description = "Assign public IPs to brokers. Required when the new VNet is not peered to the control node VNet."
  type        = bool
  default     = true
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key uploaded to all broker VMs."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ansible_run_id" {
  description = "Change this string to force Ansible re-run without destroying/recreating VMs."
  type        = string
  default     = ""
}

# ── Control node / Ansible paths ────────────────────────────────────────────

variable "repository_name" {
  description = "Repository directory name on the control node."
  type        = string
  default     = "ecom-middleware-ops1"
}

variable "control_node_user" {
  description = "Admin username of the control node (used to compute Ansible venv and repo paths)."
  type        = string
  default     = "azureadmin"
}

variable "ansible_venv_path" {
  description = "Absolute path to Ansible venv on the control node. Leave empty to auto-compute."
  type        = string
  default     = ""
}

variable "repository_base_dir" {
  description = "Absolute path to the cloned repository on the control node. Leave empty to auto-compute."
  type        = string
  default     = ""
}

variable "enable_ansible_provisioner" {
  description = "Run null_resource local-exec to configure Kafka/monitoring. Set true only when applying from Linux control node with /bin/bash and ansible-venv."
  type        = bool
  default     = false
}

variable "manage_subnet_nsg_association" {
  description = "Whether Terraform should create/manage the subnet-to-NSG association. Set false when association already exists outside Terraform state."
  type        = bool
  default     = false
}
