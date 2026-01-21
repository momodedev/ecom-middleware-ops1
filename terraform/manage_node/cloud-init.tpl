#cloud-config
# Cloud-init configuration for control node initialization (Rocky Linux 9)
# Azure-native bootstrap template for Terraform, Ansible, and Azure CLI setup

package_update: true
package_upgrade: false

packages:
  - jq
  - python3
  - python3-pip
  - python3-virtualenv
  - curl
  - wget
  - gnupg

runcmd:
  # Disable firewalld to ensure Prometheus/Grafana ports are accessible
  - systemctl disable firewalld
  - systemctl stop firewalld
  
  # Install Terraform from HashiCorp repo (Rocky Linux)
  - dnf install -y dnf-plugins-core
  - dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
  - dnf install -y terraform
  
  # Install Azure CLI (Rocky Linux)
  - rpm --import https://packages.microsoft.com/keys/microsoft.asc
  - echo "[azure-cli]" | tee /etc/yum.repos.d/azure-cli.repo
  - echo "name=Azure CLI" | tee -a /etc/yum.repos.d/azure-cli.repo
  - echo "baseurl=https://packages.microsoft.com/yumrepos/azure-cli" | tee -a /etc/yum.repos.d/azure-cli.repo
  - echo "enabled=1" | tee -a /etc/yum.repos.d/azure-cli.repo
  - echo "gpgcheck=1" | tee -a /etc/yum.repos.d/azure-cli.repo
  - echo "gpgkey=https://packages.microsoft.com/keys/microsoft.asc" | tee -a /etc/yum.repos.d/azure-cli.repo
  - dnf install -y azure-cli
  
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
