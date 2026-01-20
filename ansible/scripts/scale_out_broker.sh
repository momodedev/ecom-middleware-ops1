#!/bin/bash
# scale_out_broker.sh
# Comprehensive shell wrapper for scaling out Kafka cluster by provisioning and configuring brokers
# Usage: 
#   Single broker: ./scale_out_broker.sh --broker-name kafka-broker-3 --subscription-id <id> --resource-group kafka-t2
#   Multiple brokers: ./scale_out_broker.sh --broker-count 6 --subscription-id <id> --resource-group kafka-t2
#   (--broker-count: total desired broker count, script calculates which brokers to add)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/../.."
TERRAFORM_DIR="${PROJECT_ROOT}/terraform/kafka"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory/kafka_hosts"

# Defaults
BROKER_NAME=""
BROKER_COUNT=""
NUM_BROKERS=""
CURRENT_BROKER_COUNT=0
SUBSCRIPTION_ID=""
RESOURCE_GROUP=""
AUTO_APPROVE=false
ANSIBLE_USER="rockyadmin"
SSH_KEY=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --broker-name) BROKER_NAME="$2"; shift 2 ;;
    --broker-count) BROKER_COUNT="$2"; shift 2 ;;
    --num-brokers) NUM_BROKERS="$2"; shift 2 ;;
    --subscription-id) SUBSCRIPTION_ID="$2"; shift 2 ;;
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --auto-approve) AUTO_APPROVE=true; shift ;;
    --ansible-user) ANSIBLE_USER="$2"; shift 2 ;;
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate inputs
if [[ -z "$SUBSCRIPTION_ID" ]]; then
  log_error "subscription-id is required: --subscription-id <id>"
  exit 1
fi

if [[ -z "$RESOURCE_GROUP" ]]; then
  log_error "resource-group is required: --resource-group <name>"
  exit 1
fi

# Determine scaling mode and validate parameters
if [[ -n "$BROKER_COUNT" && -n "$BROKER_NAME" ]]; then
  log_error "Cannot specify both --broker-count and --broker-name. Use one or the other."
  exit 1
fi

# Get current broker count from inventory
if [[ -f "$INVENTORY_FILE" ]]; then
  # Count brokers with 0-indexed naming: kafka-broker-0, kafka-broker-1, etc.
  CURRENT_BROKER_COUNT=$(grep -c "^kafka-broker-" "$INVENTORY_FILE" || echo "0")
fi

# Mode 1: Single broker scale (--broker-name)
if [[ -n "$BROKER_NAME" ]]; then
  NUM_BROKERS=1
  BROKER_COUNT=$((CURRENT_BROKER_COUNT + 1))
  log_info "Single broker mode: Adding 1 broker ($BROKER_NAME)"
# Mode 2: Multi-broker scale (--broker-count)
elif [[ -n "$BROKER_COUNT" ]]; then
  if [[ $BROKER_COUNT -le $CURRENT_BROKER_COUNT ]]; then
    log_error "Target broker count ($BROKER_COUNT) must be greater than current count ($CURRENT_BROKER_COUNT)"
    exit 1
  fi
  NUM_BROKERS=$((BROKER_COUNT - CURRENT_BROKER_COUNT))
  log_info "Multi-broker mode: Adding $NUM_BROKERS brokers (scaling from $CURRENT_BROKER_COUNT to $BROKER_COUNT)"
else
  log_error "Must specify either --broker-name or --broker-count"
  exit 1
fi

# Auto-detect SSH key if not provided
if [[ -z "$SSH_KEY" ]]; then
  # Check common SSH key locations
  for key_path in ~/.ssh/id_rsa ~/.ssh/id_ed25519 ~/.ssh/id_ecdsa; do
    if [[ -f "$key_path" ]]; then
      SSH_KEY="$key_path"
      log_info "Auto-detected SSH key: $SSH_KEY"
      break
    fi
  done
fi

# Validate SSH key if provided
if [[ -n "$SSH_KEY" && ! -f "$SSH_KEY" ]]; then
  log_warn "SSH key not found: $SSH_KEY"
  SSH_KEY=""
fi

# Set Azure subscription context
log_info "Setting Azure subscription context..."
az account set --subscription "$SUBSCRIPTION_ID" || {
  log_error "Failed to set subscription context"
  exit 1
}

log_info "Kafka Cluster Scale-Out: Adding $NUM_BROKERS broker(s)"
log_info "Target Broker Count: $BROKER_COUNT"
log_info "Current Broker Count: $CURRENT_BROKER_COUNT"
log_info "Subscription ID: $SUBSCRIPTION_ID"
log_info "Resource Group: $RESOURCE_GROUP"
log_info "Ansible User: $ANSIBLE_USER"
echo ""

# Detect VM size from existing broker (if any exist)
KAFKA_VM_SIZE=""
if [[ $CURRENT_BROKER_COUNT -gt 0 ]]; then
  log_info "Detecting VM size from existing broker..."
  
  # Find first existing broker VM dynamically
  EXISTING_VM_NAME=$(az vm list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?contains(name, 'broker')].name | [0]" \
    --output tsv 2>/dev/null || echo "")
  
  if [[ -n "$EXISTING_VM_NAME" ]]; then
    log_info "Found existing broker VM: $EXISTING_VM_NAME"
    KAFKA_VM_SIZE=$(az vm show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$EXISTING_VM_NAME" \
      --query "hardwareProfile.vmSize" \
      --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$KAFKA_VM_SIZE" ]]; then
      log_success "Detected VM size from existing broker: $KAFKA_VM_SIZE"
    else
      log_warn "Could not detect VM size from $EXISTING_VM_NAME, using Terraform default"
    fi
  else
    log_warn "Could not find existing broker VMs in resource group, using Terraform default"
  fi
else
  log_info "No existing brokers found in inventory, using Terraform default VM size"
fi
echo ""

# Step 1: Provision new broker VMs via Terraform
log_info "Step 1: Provisioning $NUM_BROKERS new broker VM(s) via Terraform..."
cd "$TERRAFORM_DIR"

TERRAFORM_CMD="terraform apply -auto-approve -var ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID -var kafka_instance_count=$BROKER_COUNT"
if [[ -n "$KAFKA_VM_SIZE" ]]; then
  TERRAFORM_CMD="$TERRAFORM_CMD -var kafka_vm_size=$KAFKA_VM_SIZE"
fi

log_info "Running: $TERRAFORM_CMD"
eval "$TERRAFORM_CMD" || {
  log_error "Terraform apply failed"
  exit 1
}
log_success "Broker VMs provisioned"
echo ""

# Ensure ansible-playbook is available (prefer control node venv)
ANSIBLE_PLAYBOOK_BIN=$(command -v ansible-playbook || true)
if [[ -z "$ANSIBLE_PLAYBOOK_BIN" && -x "/home/azureadmin/ansible-venv/bin/ansible-playbook" ]]; then
  ANSIBLE_PLAYBOOK_BIN="/home/azureadmin/ansible-venv/bin/ansible-playbook"
  export PATH="/home/azureadmin/ansible-venv/bin:$PATH"
fi
if [[ -z "$ANSIBLE_PLAYBOOK_BIN" ]]; then
  log_error "ansible-playbook not found. Install Ansible or ensure /home/azureadmin/ansible-venv exists."
  exit 1
fi

# Step 2-6: For each new broker, discover IP, update inventory, deploy Kafka, validate
BROKERS_DEPLOYED=()
HEALTH_CHECK_RESULTS=()
TEMP_HEALTH_DIR=$(mktemp -d)
trap "rm -rf $TEMP_HEALTH_DIR" EXIT

for ((i=CURRENT_BROKER_COUNT; i<BROKER_COUNT; i++)); do
  BROKER_INDEX=$i
  BROKER_SEQUENCE=$((i+1))
  # Consistent 0-indexed naming across all components:
  # - Terraform Index: 0, 1, 2...
  # - Azure VM Name: kafka-t2-broker-0, kafka-t2-broker-1...
  # - Computer Name: kafka-broker-0, kafka-broker-1...
  # - Inventory Name: kafka-broker-0, kafka-broker-1...
  # - Kafka Node ID: 1, 2, 3... (1-indexed as required by KRaft)
  AZURE_VM_NAME="kafka-t2-broker-${BROKER_INDEX}"
  if [[ -n "$BROKER_NAME" ]]; then
    CURRENT_BROKER_NAME="$BROKER_NAME"
  else
    CURRENT_BROKER_NAME="kafka-broker-${BROKER_INDEX}"
  fi
  
  log_info ""
  log_info "=========================================="
  log_info "Processing broker $((i-CURRENT_BROKER_COUNT+1))/$NUM_BROKERS"
  log_info "  Inventory Name: $CURRENT_BROKER_NAME"
  log_info "  Azure VM Name: $AZURE_VM_NAME"
  log_info "  Kafka Node ID: $BROKER_SEQUENCE"
  log_info "  Terraform Index: $BROKER_INDEX"
  log_info "=========================================="
  echo ""

  # Step 2: Discover broker IP from Azure
  log_info "Step 2: Discovering broker IP for Azure VM: $AZURE_VM_NAME..."
  NEW_BROKER_IP=$(az vm list-ip-addresses \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?virtualMachine.name=='${AZURE_VM_NAME}'].virtualMachine.network.publicIpAddresses[0].ipAddress" \
    --output tsv 2>/dev/null || echo "")

  # If public IP not found, try private IP
  if [[ -z "$NEW_BROKER_IP" ]]; then
    NEW_BROKER_IP=$(az vm list-ip-addresses \
      --resource-group "$RESOURCE_GROUP" \
      --query "[?virtualMachine.name=='${AZURE_VM_NAME}'].virtualMachine.network.privateIpAddresses[0]" \
      --output tsv 2>/dev/null || echo "")
  fi

  if [[ -z "$NEW_BROKER_IP" ]]; then
    log_error "Failed to discover IP for Azure VM '$AZURE_VM_NAME' in resource group '$RESOURCE_GROUP'"
    log_error "Make sure the VM was provisioned by Terraform and exists in Azure."
    exit 1
  fi

  log_success "Broker IP: $NEW_BROKER_IP"
  echo ""

  # Step 3: Update Ansible inventory
  log_info "Step 3: Updating Ansible inventory for $CURRENT_BROKER_NAME..."
  if grep -q "^$CURRENT_BROKER_NAME" "$INVENTORY_FILE"; then
    log_warn "$CURRENT_BROKER_NAME already in inventory, skipping"
  else
    # Add broker with Kafka node ID (1-indexed)
    echo "$CURRENT_BROKER_NAME ansible_host=$NEW_BROKER_IP private_ip=$NEW_BROKER_IP kafka_node_id=$BROKER_SEQUENCE" >> "$INVENTORY_FILE"
    log_success "Added $CURRENT_BROKER_NAME (Node ID: $BROKER_SEQUENCE) to inventory"
  fi
  echo ""

  # Step 4: Run Ansible scale-out playbook for this broker
  log_info "Step 4: Deploying Kafka on $CURRENT_BROKER_NAME via Ansible..."
  cd "$ANSIBLE_DIR"

  ANSIBLE_CMD="$ANSIBLE_PLAYBOOK_BIN -i $INVENTORY_FILE -u $ANSIBLE_USER playbooks/scale_out_kafka_broker.yml -e new_broker_host=$CURRENT_BROKER_NAME"
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    ANSIBLE_CMD="$ANSIBLE_CMD -e force_overwrite=true"
  fi

  log_info "Running: $ANSIBLE_CMD"
  eval "$ANSIBLE_CMD" || {
    log_error "Ansible playbook failed for $CURRENT_BROKER_NAME"
    log_error "This could be due to SSH connectivity issues or Kafka configuration errors."
    log_error "Check: 1) VNet peering, 2) NSG rules, 3) SSH key authorization"
    exit 1
  }
  log_success "Kafka deployed on $CURRENT_BROKER_NAME"
  BROKERS_DEPLOYED+=("$CURRENT_BROKER_NAME (Azure: $AZURE_VM_NAME, Node ID: $BROKER_SEQUENCE, IP: $NEW_BROKER_IP)")
  echo ""

  # Step 5: Validate this broker
  log_info "Step 5: Validating $CURRENT_BROKER_NAME integration..."
  sleep 10  # Wait for broker to settle

  # Check if broker is reachable
  if nc -zv "$NEW_BROKER_IP" 9092 &>/dev/null; then
    log_success "Broker port 9092 is accessible on $NEW_BROKER_IP"
  else
    log_warn "Could not verify port 9092 on $NEW_BROKER_IP; firewall rules may need adjustment"
  fi

  # Test SSH connectivity after Ansible deployment
  log_info "Testing SSH connectivity for health checks..."
  if [[ -n "$SSH_KEY" ]]; then
    if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$ANSIBLE_USER@$NEW_BROKER_IP" 'echo OK' &>/dev/null; then
      log_success "SSH authentication working for $ANSIBLE_USER@$NEW_BROKER_IP"
    else
      log_warn "SSH authentication failed; some health checks may be limited"
    fi
  else
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$ANSIBLE_USER@$NEW_BROKER_IP" 'echo OK' &>/dev/null; then
      log_success "SSH authentication working for $ANSIBLE_USER@$NEW_BROKER_IP"
    else
      log_warn "SSH not configured; some health checks will be limited"
    fi
  fi

  # Run health check on this broker
  log_info "Running health check for $CURRENT_BROKER_NAME..."
  HEALTH_CHECK_FILE="$TEMP_HEALTH_DIR/${CURRENT_BROKER_NAME}_health_check.log"
  
  SSH_USER="$ANSIBLE_USER" \
  SSH_KEY="$SSH_KEY" \
  BROKER_HOST="$NEW_BROKER_IP" \
  BOOTSTRAP_SERVER="$NEW_BROKER_IP:9092" \
  "$SCRIPT_DIR/kafka_health_check.sh" > "$HEALTH_CHECK_FILE" 2>&1 || {
    log_warn "Health check had issues for $CURRENT_BROKER_NAME; see output above"
  }
  
  # Capture health check summary
  HEALTH_SUMMARY=$(grep -E "PASS|FAIL|WARN" "$HEALTH_CHECK_FILE" | grep "\[" | head -8)
  HEALTH_CHECK_RESULTS+=("$CURRENT_BROKER_NAME ($NEW_BROKER_IP)")
  HEALTH_CHECK_RESULTS+=("$HEALTH_SUMMARY")
  HEALTH_CHECK_RESULTS+=("")
  
  # Display output
  cat "$HEALTH_CHECK_FILE"
  echo ""
done

# Step 6: Summary
log_success "Scale-out complete!"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "SCALE-OUT SUMMARY"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Brokers deployed ($NUM_BROKERS total):"
for broker in "${BROKERS_DEPLOYED[@]}"; do
  echo "  ✓ $broker"
done
echo ""

# Display comprehensive health check summary
if [[ ${#HEALTH_CHECK_RESULTS[@]} -gt 0 ]]; then
  echo "════════════════════════════════════════════════════════════════"
  echo "HEALTH CHECK SUMMARY (All Deployed Brokers)"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  for item in "${HEALTH_CHECK_RESULTS[@]}"; do
    echo "$item"
  done
  echo ""
fi

echo "════════════════════════════════════════════════════════════════"
echo "CLUSTER STATUS"
echo "════════════════════════════════════════════════════════════════"
echo "Total brokers now: $BROKER_COUNT"
echo "Newly deployed brokers: $NUM_BROKERS"
echo ""
echo "Cluster information:"
echo "  ClusterID: axx7sn9iQ1KzFbF8WoOktg"
echo "  Mode: KRaft (No ZooKeeper)"
echo "  Quorum voters: 1@172.16.1.5:9093,2@172.16.1.4:9093,3@172.16.1.6:9093,4@172.16.1.7:9093,5@172.16.1.8:9093,6@172.16.1.9:9093"
echo ""
echo "Next steps:"
echo "  1. Verify cluster status: kafka-metadata-quorum.sh --bootstrap-server <broker-ip>:9092 describe --status"
echo "  2. Verify in Prometheus: curl -s http://localhost:9090/api/v1/targets | grep kafka"
echo "  3. Check topic replication: ansible -i $INVENTORY_FILE kafka -u $ANSIBLE_USER -m shell -a '/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe'"
echo "  4. Monitor in Grafana: http://<management-node>:3000"
echo "════════════════════════════════════════════════════════════════"
