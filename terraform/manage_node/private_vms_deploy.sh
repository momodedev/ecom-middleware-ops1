#!/bin/bash
# Deploy Kafka VMs using Terraform
# This script runs on the control node to deploy Kafka broker infrastructure
# (renamed from private_vmss_deploy.sh - now using VMs instead of VMSS for better control)

set -x  # Enable command echoing for debugging

# Normalize pasted values (strip smart quotes and newlines) before writing to tfvars
sanitize_var() {
    local val="$1"
    # normalize quotes/newlines
    val="${val//$'\r'/}"      # remove CR
    val="${val//$'\n'/}"      # remove newlines
    val="${val//“/\"}"      # left smart quote -> "
    val="${val//”/\"}"      # right smart quote -> "
    # drop any leading "export " if someone pasted env blocks
    val="${val#export }"
    val="${val#EXPORT }"
    # if a pasted block still contains another export, keep only the first token
    val="${val%%export *}"
    val="${val%%EXPORT *}"
    # trim surrounding whitespace
    val="${val#${val%%[![:space:]]*}}"
    val="${val%${val##*[![:space:]]}}"
    # strip surrounding quotes (repeat to collapse double quotes)
    while [ "${val#\"}" != "$val" ]; do val="${val#\"}"; done
    while [ "${val%\"}" != "$val" ]; do val="${val%\"}"; done
    echo "$val"
}

source /home/azureadmin/ansible-venv/bin/activate

REPO_DIR="ecom-middleware-ops"

cd "$REPO_DIR/terraform/kafka"
echo "ARM_SUBSCRIPTION_ID=\"$1\"" > sub_id.tfvars
echo "kafka_instance_count=${3:-3}" >> sub_id.tfvars
echo "kafka_data_disk_iops=${4:-3000}" >> sub_id.tfvars
echo "kafka_data_disk_throughput_mbps=${5:-125}" >> sub_id.tfvars
echo "kafka_vm_size=\"${6:-Standard_D8ls_v6}\"" >> sub_id.tfvars
ANSIBLE_RUN_ID="${7:-$ANSIBLE_RUN_ID}"
if [ -n "$ANSIBLE_RUN_ID" ]; then
    echo "ansible_run_id=\"$ANSIBLE_RUN_ID\"" >> sub_id.tfvars
fi
# Add Kafka resource group name and location (params 8 and 9)
if [ -n "${8}" ]; then
    echo "resource_group_name=\"${8}\"" >> sub_id.tfvars
fi
if [ -n "${9}" ]; then
    echo "resource_group_location=\"${9}\"" >> sub_id.tfvars
fi
# Add availability zone settings from environment or defaults
echo "kafka_vm_zone=\"${KAFKA_VM_ZONE:-}\"" >> sub_id.tfvars
echo "enable_availability_zones=${ENABLE_AVAILABILITY_ZONES:-true}" >> sub_id.tfvars

# Auto-enable PremiumV2 when zones are enabled, allow override
if [ "${ENABLE_AVAILABILITY_ZONES:-true}" = "true" ] && [ -n "${KAFKA_VM_ZONE}" ]; then
    USE_PREMIUM_V2_DISKS="${USE_PREMIUM_V2_DISKS:-true}"
else
    USE_PREMIUM_V2_DISKS="${USE_PREMIUM_V2_DISKS:-false}"
fi
echo "use_premium_v2_disks=${USE_PREMIUM_V2_DISKS}" >> sub_id.tfvars

# Existing VNet/Subnet wiring (optional)
if [ -n "${USE_EXISTING_KAFKA_NETWORK}" ]; then
    echo "use_existing_kafka_network=${USE_EXISTING_KAFKA_NETWORK}" >> sub_id.tfvars
fi
if [ -n "${EXISTING_KAFKA_VNET_RESOURCE_GROUP_NAME}" ]; then
    CLEAN_RG=$(sanitize_var "${EXISTING_KAFKA_VNET_RESOURCE_GROUP_NAME}")
    echo "existing_kafka_vnet_resource_group_name=\"${CLEAN_RG}\"" >> sub_id.tfvars
fi
if [ -n "${KAFKA_VNET_NAME}" ]; then
    CLEAN_VNET=$(sanitize_var "${KAFKA_VNET_NAME}")
    echo "kafka_vnet_name=\"${CLEAN_VNET}\"" >> sub_id.tfvars
fi
if [ -n "${KAFKA_SUBNET_NAME}" ]; then
    CLEAN_SUBNET=$(sanitize_var "${KAFKA_SUBNET_NAME}")
    echo "kafka_subnet_name=\"${CLEAN_SUBNET}\"" >> sub_id.tfvars
fi
if [ -n "${ENABLE_KAFKA_NAT_GATEWAY}" ]; then
    echo "enable_kafka_nat_gateway=${ENABLE_KAFKA_NAT_GATEWAY}" >> sub_id.tfvars
fi
if [ -n "${KAFKA_NSG_ID}" ]; then
    CLEAN_NSG=$(sanitize_var "${KAFKA_NSG_ID}")
    echo "kafka_nsg_id=\"${CLEAN_NSG}\"" >> sub_id.tfvars
fi
if [ -n "${ENABLE_VNET_PEERING}" ]; then
    echo "enable_vnet_peering=${ENABLE_VNET_PEERING}" >> sub_id.tfvars
fi
terraform init
# Show the rendered vars for debugging
cat sub_id.tfvars
# Force playbook rerun if ANSIBLE_RUN_ID is set
echo "DEBUG: ANSIBLE_RUN_ID = '$ANSIBLE_RUN_ID'"
if [ -n "$ANSIBLE_RUN_ID" ]; then
    echo "Tainting null_resource.launch_ansible_playbook to force playbook rerun..."
    terraform taint null_resource.launch_ansible_playbook || echo "Taint failed or resource doesn't exist yet"
fi

# Handle terraform command - 'plan' doesn't support -auto-approve
if [ "$2" = "plan" ]; then
    terraform plan -var-file='sub_id.tfvars'
else
    terraform $2 -var-file='sub_id.tfvars' -auto-approve
fi

