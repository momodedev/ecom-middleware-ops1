#!/bin/bash
# Bootstrap script for Kafka installation on each VM
# Moved from terraform/kafka/ to ansible/scripts/ for script consolidation
# This script is used as user_data in Terraform VM provisioning

set -euo pipefail

# Log output
exec > /var/log/kafka-bootstrap.log 2>&1

echo "=== Starting Kafka Bootstrap ==="
echo "Hostname: $(hostname)"
echo "Date: $(date)"

# Update system
dnf update -y
dnf install -y python3 python3-pip

# Install Ansible
pip3 install ansible

# Locate the repository (assumed pre-copied to the VM)
REPO_DIR="${REPO_DIR:-/home/azureadmin/ecom-middleware-ops}"
if [ ! -d "$REPO_DIR" ]; then
	echo "Repository not found at $REPO_DIR; aborting bootstrap"
	exit 1
fi
cd "$REPO_DIR"

# Set Kafka broker ID based on VM hostname
KAFKA_BROKER_ID=$(hostname | grep -oP '(?<=-)\d+$')
echo "Kafka Broker ID: $KAFKA_BROKER_ID"

# Run Kafka installation Ansible role locally
cd ansible
ansible-playbook -i localhost, -c local playbooks/deploy_kafka_playbook.yaml -e "kafka_node_id=${KAFKA_BROKER_ID}"

echo "=== Kafka Bootstrap Complete ==="
