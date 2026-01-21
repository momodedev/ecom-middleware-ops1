#cloud-config
# Cloud-init configuration for Kafka broker VMs (Rocky Linux 9)
# Installs system dependencies needed before Ansible configures Kafka

packages:
  - dnf-plugins-core
  - jq
  - python3
  - python3-pip
  - python3-virtualenv
  - curl
  - wget
  - git
  - nc
  - tar
  - gzip
  - java-17-openjdk
  - java-17-openjdk-devel

runcmd:
  # Update package cache
  - dnf update -y
  
  # Install firewalld for port management
  - systemctl enable firewalld
  - systemctl start firewalld
  
  # Create required directories
  - mkdir -p /opt/kafka
  - mkdir -p /data/kafka
  - mkdir -p /var/log/kafka
  
  # Format and mount data disk if attached
  - |
    if [ -b /dev/sdc ] && [ ! -d /data/kafka ] || ! mountpoint -q /data/kafka; then
      echo "Formatting and mounting data disk..."
      mkfs.ext4 -F /dev/sdc || true
      mkdir -p /data/kafka
      mount /dev/sdc /data/kafka || true
      echo "/dev/sdc /data/kafka ext4 defaults,nofail 0 2" >> /etc/fstab
      chmod 755 /data/kafka
    fi
  
  # Set up Python environment for Ansible
  - python3 -m venv /home/rockyadmin/ansible-venv || true
  - /home/rockyadmin/ansible-venv/bin/pip install --upgrade pip setuptools
  - /home/rockyadmin/ansible-venv/bin/pip install ansible jinja2 netaddr
  - chmod -R 755 /home/rockyadmin/ansible-venv
  
  # Set up system limits for Kafka
  - |
    cat >> /etc/security/limits.conf << 'EOF'
    *       soft    nofile   65536
    *       hard    nofile   65536
    *       soft    nproc    65536
    *       hard    nproc    65536
    EOF
  
  # Configure kernel parameters for Kafka performance
  - |
    cat >> /etc/sysctl.conf << 'EOF'
    # Network tuning
    net.core.rmem_max = 134217728
    net.core.wmem_max = 134217728
    net.ipv4.tcp_rmem = 4096 87380 67108864
    net.ipv4.tcp_wmem = 4096 65536 67108864
    net.tcp_max_syn_backlog = 1024
    net.ipv4.ip_local_port_range = 1024 65535
    EOF
  - sysctl -p
  
  # Log cloud-init completion
  - echo "Cloud-init bootstrap completed at $(date)" > /var/log/kafka-bootstrap-complete.log
