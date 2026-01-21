#cloud-config
# Cloud-init configuration for control node initialization
# Replaces private_vms_init.sh with idempotent, Azure-native bootstrap

package_update: true
package_upgrade: false

packages:
  - jq
  - python3-venv
  - python3-pip
  - curl
  - wget
  - gnupg

runcmd:
  # Disable UFW to ensure Prometheus/Grafana ports are accessible
  - systemctl disable ufw
  - systemctl stop ufw
  
  # Install Terraform from HashiCorp repo
  - wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  - echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrkins/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
  - apt update
  - apt install -y terraform
  
  # Install Azure CLI
  - curl -sL https://aka.ms/InstallAzureCLIDeb | bash
  
  # Setup Ansible venv as azureadmin user
  - su - azureadmin -c 'python3 -m venv /home/azureadmin/ansible-venv'
  - su - azureadmin -c '/home/azureadmin/ansible-venv/bin/pip install ansible'
  - su - azureadmin -c '/home/azureadmin/ansible-venv/bin/ansible-galaxy collection install azure.azcollection --force'
  - su - azureadmin -c '/home/azureadmin/ansible-venv/bin/pip install -r /home/azureadmin/.ansible/collections/ansible_collections/azure/azcollection/requirements.txt'
  
  # Generate SSH key for azureadmin (skip if exists)
  - su - azureadmin -c 'test -f /home/azureadmin/.ssh/id_rsa || ssh-keygen -t rsa -N "" -f /home/azureadmin/.ssh/id_rsa'
  
  # Login to Azure using managed identity (control node has Contributor role)
  - su - azureadmin -c 'az login --identity'
  
  # Signal completion
  - touch /var/lib/cloud/instance/control-node-initialized

write_files:
  - path: /etc/profile.d/ansible-env.sh
    permissions: '0644'
    content: |
      # Auto-activate Ansible venv for azureadmin
      if [ "$USER" = "azureadmin" ] && [ -f "$HOME/ansible-venv/bin/activate" ]; then
        source "$HOME/ansible-venv/bin/activate"
      fi

final_message: "Control node initialization complete after $UPTIME seconds"
