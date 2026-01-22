#cloud-config
# Cloud-init configuration for Kafka broker VMs (Rocky Linux 9)
# Installs system dependencies needed before Ansible configures Kafka

packages:
  - dnf-plugins-core
  - jq
  - python3
  - python3-pip
  - python3-venv
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
  
  # Create required directories with proper ownership
  - mkdir -p /opt/kafka
  - mkdir -p /data/kafka
  - mkdir -p /var/log/kafka
  
  # Create kafka user and group early (Ansible will reuse)
  - groupadd -f kafka || true
  - useradd -r -g kafka -s /bin/bash kafka || true
  
  # Format and mount data disk if attached
  - |
    if [ -b /dev/sdc ]; then
      if ! mountpoint -q /data/kafka; then
        echo "Formatting and mounting data disk..."
        mkfs.ext4 -F /dev/sdc 2>/dev/null || true
        mount /dev/sdc /data/kafka 2>/dev/null || true
        if ! grep -q "/dev/sdc" /etc/fstab; then
          echo "/dev/sdc /data/kafka ext4 defaults,nofail 0 2" >> /etc/fstab
        fi
        chmod 755 /data/kafka
        chown kafka:kafka /data/kafka
      fi
    fi
  
  # Set up Python environment for Ansible
  - python3 -m venv /home/${kafka_admin_username}/ansible-venv || true
  - /home/${kafka_admin_username}/ansible-venv/bin/pip install --upgrade pip setuptools
  - /home/${kafka_admin_username}/ansible-venv/bin/pip install ansible jinja2 netaddr
  - chmod -R 755 /home/${kafka_admin_username}/ansible-venv
  
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
