#!/usr/bin/env bash
# Validate that VMs are ready for Ansible deployment
# This script checks VM provisioning state and SSH connectivity

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <resource-group> <admin-username>" >&2
    echo "Example: $0 kafka-cluster rockyadmin" >&2
    exit 1
fi

RESOURCE_GROUP="$1"
ADMIN_USER="$2"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"

echo "=========================================="
echo "VM Readiness Validation"
echo "=========================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Admin User: $ADMIN_USER"
echo "SSH Key: $SSH_KEY"
echo ""

# Check if logged in to Azure
echo "[1/5] Checking Azure authentication..."
if ! az account show &>/dev/null; then
    echo "ERROR: Not logged in to Azure. Run 'az login --identity' first."
    exit 1
fi
echo "✓ Azure authentication OK"
echo ""

# Get all Kafka broker VMs
echo "[2/5] Discovering Kafka broker VMs..."
vm_names=$(az vm list -g "$RESOURCE_GROUP" \
    --query "[?starts_with(name, '${resource_group}-broker-')].name" \
    -o tsv | sort)

if [[ -z "$vm_names" ]]; then
    echo "ERROR: No Kafka broker VMs found in resource group $RESOURCE_GROUP"
    exit 1
fi

vm_count=$(echo "$vm_names" | wc -l | tr -d ' ')
echo "✓ Found $vm_count Kafka broker VMs"
echo ""

# Check provisioning state of each VM
echo "[3/5] Checking VM provisioning states..."
failed_vms=0
for vm_name in $vm_names; do
    state=$(az vm get-instance-view -g "$RESOURCE_GROUP" -n "$vm_name" \
        --query "instanceView.statuses[?starts_with(code, 'ProvisioningState')].displayStatus" \
        -o tsv)

    power_state=$(az vm get-instance-view -g "$RESOURCE_GROUP" -n "$vm_name" \
        --query "instanceView.statuses[?starts_with(code, 'PowerState')].displayStatus" \
        -o tsv)

    if [[ "$state" != "Provisioning succeeded" ]]; then
        echo "✗ $vm_name: Provisioning State = $state"
        ((failed_vms++))
        continue
    fi

    if [[ "$power_state" != "VM running" ]]; then
        echo "✗ $vm_name: Power State = $power_state (attempting start)"
        if az vm start -g "$RESOURCE_GROUP" -n "$vm_name" >/dev/null 2>&1; then
            for attempt in {1..6}; do
                sleep 10
                power_state=$(az vm get-instance-view -g "$RESOURCE_GROUP" -n "$vm_name" \
                    --query "instanceView.statuses[?starts_with(code, 'PowerState')].displayStatus" \
                    -o tsv)
                if [[ "$power_state" == "VM running" ]]; then
                    break
                fi
            done
        else
            echo "✗ $vm_name: Failed to start VM"
        fi
    fi

    if [[ "$power_state" != "VM running" ]]; then
        ((failed_vms++))
    else
        echo "✓ $vm_name: $state, $power_state"
    fi
done

if [[ $failed_vms -gt 0 ]]; then
    echo ""
    echo "ERROR: $failed_vms VMs are not in ready state"
    exit 1
fi
echo ""

# Get private IPs
echo "[4/5] Retrieving private IP addresses..."
declare -A vm_ips
for vm_name in $vm_names; do
    private_ip=$(az vm list-ip-addresses -g "$RESOURCE_GROUP" -n "$vm_name" \
        --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv)
    
    if [[ -z "$private_ip" || "$private_ip" == "null" ]]; then
        echo "✗ $vm_name: No private IP found"
        exit 1
    fi
    
    vm_ips["$vm_name"]="$private_ip"
    echo "✓ $vm_name: $private_ip"
done
echo ""

# Test SSH connectivity to each VM
echo "[5/5] Testing SSH connectivity (may take a few minutes)..."
ssh_failed=0
for vm_name in $vm_names; do
    ip="${vm_ips[$vm_name]}"
    
    echo -n "Testing $vm_name ($ip)... "
    
    # Try SSH with timeout
    if timeout 30 ssh -o StrictHostKeyChecking=no \
                       -o ConnectTimeout=10 \
                       -o BatchMode=yes \
                       -i "$SSH_KEY" \
                       "${ADMIN_USER}@${ip}" \
                       "echo 'SSH OK'" &>/dev/null; then
        echo "✓ Connected"
    else
        echo "✗ Failed"
        ((ssh_failed++))
    fi
done

echo ""
echo "=========================================="
if [[ $ssh_failed -eq 0 ]]; then
    echo "✅ All VMs are ready for deployment!"
    echo "=========================================="
    exit 0
else
    echo "❌ $ssh_failed VMs failed SSH connectivity test"
    echo "=========================================="
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Wait 2-3 minutes for VMs to finish cloud-init"
    echo "2. Check NSG rules allow SSH from control node"
    echo "3. Verify VNet peering is active"
    echo "4. Check if SSH key is authorized: cat ~/.ssh/id_rsa.pub"
    echo ""
    exit 1
fi
