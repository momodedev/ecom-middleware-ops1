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

# Fix DNS first (CentOS OpenLogic images sometimes miss working resolvers).
ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "sudo bash -lc 'printf \"nameserver 168.63.129.16\\nnameserver 1.1.1.1\\n\" > /etc/resolv.conf'" \
  || true

# Replace all legacy/mirrorlist repos with CentOS 7.9 vault repos.
ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "sudo bash -lc 'for f in /etc/yum.repos.d/*.repo; do mv \"\$f\" \"\$f.disabled\" || true; done; cat > /etc/yum.repos.d/CentOS-Vault.repo <<\"EOF\"
[base]
name=CentOS-7.9.2009 - Base
baseurl=http://vault.centos.org/7.9.2009/os/\$basearch/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[updates]
name=CentOS-7.9.2009 - Updates
baseurl=http://vault.centos.org/7.9.2009/updates/\$basearch/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[extras]
name=CentOS-7.9.2009 - Extras
baseurl=http://vault.centos.org/7.9.2009/extras/\$basearch/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF'" \
  || true

ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "sudo yum clean all; sudo rm -rf /var/cache/yum; sudo yum makecache -y" \
  || true

# Bootstrap Python and Java using raw (works even when python is initially absent).
ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "test -x /usr/bin/python || (sudo yum -y install python || sudo yum -y install python2 || true)" \
  || true

ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "test -x /usr/bin/python3 || (sudo yum -y install python3 || sudo yum -y install python36 || true)" \
  || true

ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "rpm -q java-11-openjdk >/dev/null 2>&1 || sudo yum -y install java-11-openjdk java-11-openjdk-devel" \
  || true

ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "test -x /usr/bin/python || test ! -x /usr/bin/python3 || sudo ln -sf /usr/bin/python3 /usr/bin/python" \
  || true

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i "$BASE_DIR/inventory/kafka_hosts" "$BASE_DIR/playbooks/deploy_kafka_playbook.yml"
ansible-playbook -i "$BASE_DIR/inventory/inventory.ini" "$BASE_DIR/playbooks/deploy_monitoring_playbook.yml"

echo "CentOS Kafka + monitoring deployment completed."
