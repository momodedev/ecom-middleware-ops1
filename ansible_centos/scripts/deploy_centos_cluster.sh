#!/usr/bin/env bash
# End-to-end deploy for CentOS broker lane using ansible_centos wrappers.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <resource-group> <broker-admin-username> [control-node-username]" >&2
  exit 1
fi

RESOURCE_GROUP="$1"
BROKER_USER="$2"
CONTROL_USER="${3:-azureadmin}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ERROR: ansible-playbook not found in PATH. Activate ansible-venv first." >&2
  exit 1
fi

bash "$SCRIPT_DIR/generate_inventory_centos.sh" "$RESOURCE_GROUP" "$BROKER_USER" "$CONTROL_USER"

# Bootstrap Python on brokers using raw (does not require Python on remote).
# This prevents early playbook tasks from failing when /usr/bin/python3 is missing.
ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "test -x /usr/bin/python || (sudo yum -y install python || sudo yum -y install python2)" \
  || true

ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "test -x /usr/bin/python3 || (sudo yum -y install python3 || sudo yum -y install python36 || true)" \
  || true

ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "test -x /usr/bin/python || sudo ln -sf /usr/bin/python3 /usr/bin/python" \
  || true

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i "$BASE_DIR/inventory/kafka_hosts" "$BASE_DIR/playbooks/deploy_kafka_playbook.yml"
ansible-playbook -i "$BASE_DIR/inventory/inventory.ini" "$BASE_DIR/playbooks/deploy_monitoring_playbook.yml"

echo "CentOS Kafka + monitoring deployment completed."
