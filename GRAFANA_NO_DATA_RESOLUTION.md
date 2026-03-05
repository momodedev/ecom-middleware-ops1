# Kafka KRaft Monitoring - Data Resolution Guide

## Problem
The Grafana dashboard for Kafka KRaft cluster was showing "No data" across all panels. This was caused by multiple configuration mismatches:

1. **Datasource Mismatch**: Dashboard referenced `Managed_Prometheus_azuremonitor` but Grafana had only `Prometheus` configured
2. **Job Label Mismatch**: Dashboard queried `job="kafka-broker"` but Prometheus had `kafka-exporter` and `node-exporter` jobs
3. **Missing JMX Exporter**: Kafka brokers weren't configured to expose JMX metrics on port 9999
4. **Incomplete Prometheus Configuration**: No scrape job for JMX metrics

## Solutions Implemented

### 1. Enabled JMX Exporter on Kafka Brokers
**File**: `ansible/roles/kafka/templates/kafka.service.j2`

Added JMX configuration to Kafka systemd service:
```yaml
Environment="KAFKA_JMX_OPTS=-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname={{ ansible_default_ipv4.address }} -Dcom.sun.management.jmxremote.rmi.port=9999"
Environment="JMX_PORT=9999"
```

**Impact**: Kafka brokers now expose JMX metrics on port 9999

### 2. Added Prometheus Scrape Job for JMX
**File**: `ansible/roles/monitoring/prometheus_grafana/templates/prometheus.yml.j2`

Added new scrape configuration:
```yaml
- job_name: 'kafka-jmx'
  file_sd_configs:
    - files:
        - '/etc/prometheus/file_sd/kafka_jmx_targets.json'
      refresh_interval: 30s
```

**Impact**: Prometheus now scrapes JMX metrics from all Kafka brokers

### 3. Created JMX Targets Discovery Template
**File**: `ansible/roles/kafka/templates/prometheus_kafka_jmx_targets.json.j2`

New template generates JMX broker targets:
```json
[
  {
    "labels": {
      "job": "kafka-jmx"
    },
    "targets": [
      "10.0.1.6:9999",
      "10.0.1.4:9999",
      "10.0.1.5:9999"
    ]
  }
]
```

**Impact**: Dynamic JMX target discovery based on Kafka inventory

### 4. Updated Playbook to Render JMX Targets
**File**: `ansible/playbooks/deploy_kafka_playbook.yaml`

Added task to render JMX targets:
```yaml
- name: Render Kafka JMX scrape target file
  template:
    src: ../roles/kafka/templates/prometheus_kafka_jmx_targets.json.j2
    dest: "{{ prometheus_jmx_output_path }}"
    mode: "0644"
```

**Impact**: JMX targets file is generated during deployment

### 5. Fixed Dashboard Datasource and Queries
**File**: `ansible/files/dashboards/kafka_kraft_dashboard.json`

Updated using Python script:
- Changed datasource from `Managed_Prometheus_azuremonitor` → `Prometheus`
- Changed Kafka metric queries from `job="kafka-broker"` → `job="kafka-jmx"`
- Changed node metrics from `job="kafka-jmx"` → `job="node-exporter"`

**Impact**: Dashboard queries now match Prometheus job labels

### 6. Created Prometheus file_sd Directory
**File**: `ansible/roles/monitoring/prometheus_grafana/tasks/main.yml`

Added directory creation:
```yaml
- /etc/prometheus/file_sd
```

**Impact**: Ensures directory exists for dynamic service discovery files

## Metric Flow Architecture

```
Kafka Brokers (Port 9999)
    ↓ JMX Exporter
    ↓
Prometheus (kafka-jmx job)
    ↓ Scrapes every 15s
    ↓
Grafana Dashboard
    ↓ Queries on 10s refresh
    ↓
Real-time Kafka Cluster Metrics
```

## Verification Steps

1. **SSH into a Kafka broker** and check JMX is running:
   ```bash
   netstat -tlnp | grep 9999
   ```

2. **Check Prometheus targets** at `http://prometheus-ip:9090/targets`:
   - Should see `kafka-jmx` job with 3 targets
   - Should see `kafka-exporter` job with 3 targets
   - Should see `node-exporter` job with 3+ targets

3. **Verify metrics in Prometheus** at `http://prometheus-ip:9090`:
   - Search for `kafka_server_BrokerTopicMetrics_BytesInPerSec_total{job="kafka-jmx"}`
   - Should return non-empty results

4. **Check Grafana dashboard** at `http://grafana-ip:3000`:
   - Navigate to Kafka Cluster - KRaft Mode dashboard
   - All panels should display data
   - Brokers Online should show 3
   - Memory, CPU, Disk metrics should populate

## Metrics Available

### Kafka JMX Metrics (job="kafka-jmx")
- `kafka_server_BrokerTopicMetrics_*` - Topic-level metrics
- `kafka_server_DelayedOperationPurgatory_*` - Delayed operations
- `kafka_server_ReplicaManager_*` - Replication metrics
- `kafka_raft_*` - KRaft-specific metrics
- JVM metrics (heap, GC, threads)

### Node Exporter Metrics (job="node-exporter")
- `node_memory_*` - Memory statistics
- `node_cpu_*` - CPU usage
- `node_filesystem_*` - Disk space
- `node_filefd_*` - File descriptor usage

### Kafka Exporter Metrics (job="kafka-exporter")
- Consumer group metrics
- Topic partition metrics
- Broker connection status

## Next Steps

1. **Deploy with fixes**:
   ```bash
   terraform apply -auto-approve -var-file=secret.tfvars
   ```

2. **Monitor deployment** for 2-3 minutes to allow:
   - Kafka brokers to start JMX services
   - Prometheus to discover targets
   - Grafana dashboard to populate

3. **Troubleshoot if needed**:
   - Check Prometheus logs for scrape errors
   - Verify firewall allows port 9999
   - Check network connectivity between nodes

## Files Modified
1. `ansible/roles/kafka/templates/kafka.service.j2` - Added JMX configuration
2. `ansible/roles/kafka/templates/prometheus_kafka_jmx_targets.json.j2` - Created new file
3. `ansible/roles/monitoring/prometheus_grafana/templates/prometheus.yml.j2` - Added kafka-jmx job
4. `ansible/roles/monitoring/prometheus_grafana/tasks/main.yml` - Added file_sd directory
5. `ansible/playbooks/deploy_kafka_playbook.yaml` - Added JMX targets rendering
6. `ansible/files/dashboards/kafka_kraft_dashboard.json` - Fixed datasource and queries

