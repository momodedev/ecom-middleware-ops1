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
