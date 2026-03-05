# Kafka & ZooKeeper Monitoring Dashboards - Implementation Guide

## Overview
This document describes the enhanced monitoring dashboards for Kafka Cluster and ZooKeeper that have been implemented based on production monitoring requirements.

---

## 1. Kafka Cluster Dashboard

### Purpose
Comprehensive monitoring of Kafka broker health, performance, and operational metrics.

### Key Metrics Implemented

#### 1.1 Cluster Health Indicators (Top Row)
| Metric | Description | Threshold | Alert Level |
|--------|-------------|-----------|------------|
| **Brokers Online** | Number of active brokers in the cluster | 3+ | Critical if < 2 |
| **Active Controllers** | Number of active Kafka controllers | 1 | Critical if != 1 |
| **Unclean Leader Election Rate** | Rate of unclean leader elections | 0 | Critical if > 0 |
| **Under Replicated Partitions** | Count of under-replicated partitions | 0 | Critical if > 0 |

#### 1.2 System Resource Metrics (Second Row)
- **Memory Usage**: Tracks heap memory consumption across brokers
- **CPU Usage**: Monitors CPU utilization (target: <80%)
- **Available Disk Space**: Disk space availability (warn if <20%)
- **Open File Descriptors**: Tracks file descriptor usage

#### 1.3 JVM Metrics (Third Row)
- **JVM Memory Used**: Active JVM heap memory
- **JVM GC Time**: Garbage collection duration in milliseconds
- **JVM GC Count**: Frequency of garbage collection events
- **JVM Thread Count**: Number of active JVM threads

#### 1.4 Throughput Metrics (Bottom Rows)
- **Total Incoming Byte Rate**: Aggregate bytes received per second
- **Total Outgoing Byte Rate**: Aggregate bytes sent per second
- **Byte Rate**: Time-series of both incoming and outgoing traffic
- **Messages In Per Second**: Message ingestion rate
- **Incoming Messages Rate**: Current message arrival rate
- **Total Produce Request Rate**: Request processing rate

### Data Sources
- **Prometheus**: Metrics scraped from Kafka JMX exporter
- **Node Exporter**: System-level metrics (CPU, memory, disk)
- **Job Labels**: `kafka-broker`, `kafka-cluster`

### PromQL Queries Used
```promql
# Cluster Health
sum(kafka_server_ReplicaManager_LeaderCount)  # Brokers online
sum(kafka_controller_KafkaController_ActiveControllerCount)  # Active controllers

# Resource Monitoring
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes  # Memory usage
1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))  # CPU usage
node_filesystem_avail_bytes{mountpoint="/"}  # Disk space

# Throughput
rate(kafka_server_BrokerTopicMetrics_BytesInPerSec_total[5m])  # Incoming bytes
rate(kafka_server_BrokerTopicMetrics_MessagesInPerSec_total[5m])  # Messages in
```

### Refresh Interval
- **10 seconds** - Provides real-time monitoring without excessive Prometheus load

### Time Range
- **Default View**: Last 1 hour
- **Customizable**: Users can adjust via time picker

---

## 2. ZooKeeper Dashboard

### Purpose
Monitor ZooKeeper ensemble health, quorum status, and operational performance.

### Key Metrics Implemented

#### 2.1 Ensemble Health (Top Row)
| Metric | Description | Threshold | Alert Level |
|--------|-------------|-----------|------------|
| **Quorum Size** | Number of ZooKeeper nodes in ensemble | 3+ | Critical if < majority |
| **Active Connections** | Number of client connections | 3+ | Warning if declining |
| **Outstanding Requests** | Pending client requests | < 100 | Critical if > 200 |
| **Request Latency - Average** | Avg response time in ms | < 10ms | Warning if > 50ms |

#### 2.2 ZNode Management (Middle Row)
- **Number of ZNodes**: Total ZNodes in ZooKeeper (healthy: 36 in test cluster)
- **Number of Watchers**: Active watch registrations (healthy: 19)

#### 2.3 System Resource Metrics
- **Memory Usage**: ZooKeeper process memory consumption
- **CPU Usage**: CPU utilization per ZooKeeper node
- **Available Disk Space**: Available storage for transaction logs
- **Open File Descriptors**: Tracks connection limits

#### 2.4 JVM Metrics
- **JVM Memory Used**: ZooKeeper heap memory
- **JVM GC Time**: Garbage collection overhead
- **JVM GC Count**: GC frequency indicator
- **JVM Thread Count**: Active threads in ZooKeeper

### Data Sources
- **Prometheus**: Metrics from ZooKeeper JMX exporter
- **Node Exporter**: System metrics
- **Job Labels**: `zookeeper`, `kafka-cluster`

### PromQL Queries Used
```promql
# Ensemble Health
count(zk_server_quorum_votes)  # Quorum size
sum(zk_connections_alive)  # Active connections
zk_outstanding_requests  # Pending requests
avg(zk_avg_latency)  # Request latency

# ZNode Management
sum(zk_znode_count)  # Total ZNodes
sum(zk_watch_count)  # Total watchers

# Resource Monitoring
zk_server_heap_mem_usage  # Heap memory
rate(zk_server_gc_time_ms_total[5m])  # GC time
zk_server_threads  # Thread count
```

### Refresh Interval
- **10 seconds** - Real-time ensemble monitoring

### Time Range
- **Default View**: Last 1 hour
- **Customizable**: Full time picker support

---

## 3. Implementation Requirements

### 3.1 Prometheus Configuration
Ensure metrics are being scraped from:
1. **Kafka Brokers** (port 9092 + JMX exporter)
2. **ZooKeeper Nodes** (port 2181 + JMX exporter)
3. **Node Exporters** (port 9100 on all hosts)

### 3.2 Grafana Provisioning
The dashboards are deployed via Ansible:
```yaml
# Grafana provisioning directory
/etc/grafana/provisioning/dashboards/ansible/
```

Files to be provisioned:
- `kafka_cluster_dashboard.json`
- `zookeeper_dashboard.json`

### 3.3 JMX Exporter Configuration
Both Kafka and ZooKeeper require JMX exporters for metric collection:

**Kafka Broker JMX Port**: 9999 (via JMX_PORT environment variable)
**ZooKeeper JMX Port**: 9010 (configured in zkServer.sh)

### 3.4 Alerting Rules (Recommended)
```yaml
groups:
  - name: kafka
    rules:
      - alert: KafkaUnderReplicatedPartitions
        expr: sum(kafka_server_ReplicaManager_UnderReplicatedPartitions) > 0
        for: 5m
      
      - alert: KafkaBrokerDown
        expr: sum(kafka_server_ReplicaManager_LeaderCount) < 3
        for: 1m
      
      - alert: UncleanLeaderElections
        expr: increase(kafka_controller_KafkaController_UncleanLeaderElectionsPerSec[5m]) > 0
        for: 1m

  - name: zookeeper
    rules:
      - alert: ZooKeeperHighLatency
        expr: avg(zk_avg_latency) > 50
        for: 5m
      
      - alert: ZooKeeperHighOutstandingRequests
        expr: max(zk_outstanding_requests) > 200
        for: 2m
```

---

## 4. Dashboard Usage

### 4.1 Kafka Cluster Dashboard
1. **Quick Health Check**: Look at the four stat panels at top - all should show healthy values
2. **Resource Trending**: Review graphs for memory, CPU, and disk usage patterns
3. **Throughput Analysis**: Monitor byte rates and message rates during peak hours
4. **Performance Investigation**: Check JVM metrics when brokers are slow

### 4.2 ZooKeeper Dashboard
1. **Ensemble Status**: Verify all ZooKeeper nodes are in quorum
2. **Connection Health**: Monitor active connections and outstanding requests
3. **Latency Trends**: Track request latency to identify performance issues
4. **Capacity Planning**: Use ZNode and watcher counts to plan scaling

### 4.3 Troubleshooting Scenarios

**Scenario 1: Broker Performance Degradation**
- Check CPU and Memory Usage graphs
- Review JVM GC Time - high GC indicates memory pressure
- Check disk space - low disk can trigger compaction

**Scenario 2: High Message Loss**
- Check Under Replicated Partitions stat
- Review Unclean Leader Election Rate
- Check network connectivity via byte rates

**Scenario 3: ZooKeeper Latency**
- Check Outstanding Requests graph
- Review Request Latency chart
- Monitor JVM GC and memory usage
- Verify disk I/O on ZooKeeper servers

---

## 5. File Locations

```
ansible/
├── files/
│   └── dashboards/
│       ├── kafka_cluster_dashboard.json      # Main Kafka monitoring
│       ├── zookeeper_dashboard.json          # ZooKeeper monitoring
│       └── node_exporter_dashboard.json      # System metrics
├── roles/
│   └── monitoring/
│       └── prometheus_grafana/
│           └── tasks/
│               └── main.yml                  # Deployment playbook
```

---

## 6. Deployment

### 6.1 Via Ansible
```bash
# Deploy monitoring stack with dashboards
ansible-playbook ansible/playbooks/deploy_monitoring_playbook.yml

# Specific dashboard deployment
ansible-playbook ansible/roles/monitoring/prometheus_grafana/tasks/main.yml
```

### 6.2 Manual Import
1. Access Grafana UI (typically http://grafana-host:3000)
2. Home → Dashboards → Import
3. Upload JSON files or paste content
4. Select Prometheus as data source
5. Save dashboard

---

## 7. Customization Guide

### 7.1 Adding Custom Metrics
1. Edit the dashboard JSON
2. Add new panel object with:
   - Unique `id` (increment from last)
   - PromQL `expr` targeting your metric
   - Appropriate `unit` and `fieldConfig`
3. Update `gridPos` for layout positioning

### 7.2 Adjusting Thresholds
Modify stat panel thresholds in `fieldConfig.defaults.thresholds.steps`:
```json
"thresholds": {
  "mode": "absolute",
  "steps": [
    {"color": "green", "value": null},
    {"color": "yellow", "value": 5},
    {"color": "red", "value": 10}
  ]
}
```

### 7.3 Changing Time Ranges
Update dashboard `time` section:
```json
"time": {
  "from": "now-6h",  // Change to desired range
  "to": "now"
}
```

---

## 8. Performance Considerations

- **Metric Cardinality**: Partition-level metrics can create high cardinality - use `topk()` in queries if needed
- **Retention Period**: Ensure Prometheus retention covers historical analysis needs (minimum 7 days recommended)
- **Query Optimization**: Use aggregation (`sum`, `avg`) for cluster-wide views rather than per-partition
- **Scrape Interval**: Recommended 15 seconds for Prometheus scrape interval

---

## 9. Troubleshooting Dashboard Issues

### No Data Appearing
1. Check Prometheus datasource configuration in Grafana
2. Verify metrics exist: `curl http://prometheus:9090/api/v1/query?query=kafka_server_ReplicaManager_LeaderCount`
3. Check metric labels match query filters (e.g., `job="kafka-broker"`)

### Dashboard Performance Slow
1. Reduce query time range
2. Simplify queries using aggregation
3. Check Prometheus resource usage
4. Consider increasing Prometheus memory allocation

### Metrics Missing or Gaps
1. Verify JMX exporter is running on Kafka/ZooKeeper
2. Check network connectivity between hosts
3. Verify Prometheus scrape targets are "UP": http://prometheus:9090/targets

---

## 10. Version Information

- **Grafana**: 8.0+
- **Prometheus**: 2.30+
- **Schema Version**: 38 (latest JSON dashboard format)
- **Dashboard Version**: 2

---

## Appendix: Metric Glossary

| Metric | Type | Description |
|--------|------|-------------|
| `kafka_server_ReplicaManager_LeaderCount` | Gauge | Number of leader partitions |
| `kafka_controller_KafkaController_ActiveControllerCount` | Gauge | Active controller count |
| `kafka_server_ReplicaManager_UnderReplicatedPartitions` | Gauge | Partitions without full replicas |
| `kafka_server_BrokerTopicMetrics_BytesInPerSec_total` | Counter | Total bytes received |
| `kafka_server_BrokerTopicMetrics_MessagesInPerSec_total` | Counter | Total messages received |
| `zk_connections_alive` | Gauge | Active client connections |
| `zk_avg_latency` | Gauge | Average request latency (ms) |
| `zk_znode_count` | Gauge | Total ZNodes in ensemble |
| `zk_watch_count` | Gauge | Total active watches |
| `zk_outstanding_requests` | Gauge | Pending client requests |

