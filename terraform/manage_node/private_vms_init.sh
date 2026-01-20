#!/bin/bash
# Initialize control node for Kafka VM deployment
# This script prepares the control node with necessary tools and code
# (renamed from private_vmss_init.sh - now using VMs instead of VMSS for better control)

set -e
export DEBIAN_FRONTEND=noninteractive

# Download HashiCorp GPG key and import it (use -O - to stdout, force overwrite with sudo)
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg --yes --batch --no-tty
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform jq -y

# Explicitly disable UFW to ensure ports 3000/9090 are reachable relative to Azure NSG
sudo ufw disable

sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3-venv

curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

mkdir ansible-venv
python3 -m venv ansible-venv/
source ansible-venv/bin/activate

python3 -m pip install ansible
ansible-galaxy collection install azure.azcollection --force
python3 -m pip install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements.txt

ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa <<< y

REPO_DIR="ecom-middleware-ops"

#/var/lib/waagent/custom-script/download/0
