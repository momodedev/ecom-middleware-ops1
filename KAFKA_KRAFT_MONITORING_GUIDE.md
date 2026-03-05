# Kafka Cluster KRaft Mode - Monitoring Dashboard Implementation Guide

## Overview
This document describes the monitoring dashboard for Kafka Cluster running in **KRaft (Kafka Raft) mode**. KRaft is the new consensus protocol that eliminates the need for ZooKeeper by embedding distributed consensus directly into Kafka.

---

## 1. Kafka KRaft Cluster Dashboard

### Purpose
Comprehensive monitoring of Kafka KRaft brokers, quorum health, replication, and operational metrics without external ZooKeeper dependency.

### Key Differences from ZooKeeper Mode
| Aspect | ZooKeeper Mode | KRaft Mode |
|--------|--|--|
| **External Dependency** | Requires ZooKeeper ensemble | No external dependency |
| **Controller** | Separate ZooKeeper nodes | Co-located with broker nodes |
| **Quorum Management** | ZooKeeper handles consensus | Kafka Raft protocol |
| **Metadata Storage** | Stored in ZooKeeper | Stored in `__cluster_metadata` topic |
| **Complexity** | Dual cluster management | Single cluster management |

### 1.1 Cluster Health Indicators (Top Row)
| Metric | Description | Healthy Value | Alert Threshold |
|--------|-------------|---|---|
| **Brokers Online** | Number of active brokers | 3+ | Critical if < majority |
| **KRaft Leaders** | Number of KRaft leader processes | 1 | Critical if != 1 |
| **Under Replicated Partitions** | Partitions lacking full replicas | 0 | Critical if > 0 |
| **KRaft Quorum Size** | Size of the KRaft quorum | 3+ | Critical if < majority |

### 1.2 System Resource Metrics (Second Row)
- **Memory Usage**: Heap memory consumption tracking
- **CPU Usage**: CPU utilization per broker (target: <80%)
- **Available Disk Space**: Free disk space (warn if <20%)
- **Open File Descriptors**: File descriptor consumption tracking

### 1.3 JVM Metrics (Third Row)
- **JVM Memory Used**: Active JVM heap memory allocation
- **JVM GC Time**: Garbage collection pause duration
- **JVM GC Count**: Frequency of GC events
- **JVM Thread Count**: Active threads in JVM

### 1.4 Throughput Metrics (Fourth Row)
- **Total Incoming Byte Rate**: Aggregate bytes received across cluster
- **Total Outgoing Byte Rate**: Aggregate bytes sent from cluster
- **Byte Rate (Per Broker)**: Individual broker incoming/outgoing traffic

### 1.5 Message Throughput Metrics (Fifth Row)
- **Messages In Per Second**: Message ingestion rate per broker
- **KRaft Leader Election Rate**: Frequency of leader elections (should be 0 during stability)

### 1.6 KRaft-Specific Metrics (Sixth Row)
| Metric | Description | Normal Behavior |
|--------|---|---|
| **KRaft Log End Offset** | Latest offset in quorum log | Incrementing |
| **KRaft High Water Mark** | Replicated offset across majority | Following Log End Offset closely |

### 1.7 KRaft Quorum Health (Bottom Row)
- **KRaft Quorum Request Latency**: Latency of quorum operations (should be < 10ms)
- **KRaft Uncommitted Records**: Records not yet committed to quorum (should be near 0)

### Data Sources
- **Prometheus**: Metrics from Kafka JMX exporter on all brokers
- **Node Exporter**: System-level metrics (CPU, memory, disk)
- **Job Labels**: `kafka-broker`, `kafka-cluster`

### Critical PromQL Queries for KRaft

```promql
# Broker Health
count(kafka_server_BrokerTopicMetrics_BytesInPerSec_total{job="kafka-broker"})  # Brokers online

# KRaft Quorum Status
count(kafka_raft_Quorum_Leader{job="kafka-broker"} > 0)  # KRaft leaders
count(kafka_raft_Quorum_State{job="kafka-broker"})  # Quorum size

# Replication Health
sum(kafka_server_ReplicaManager_UnderReplicatedPartitions)  # URP status

# KRaft Log Replication
kafka_raft_Replica_LogEndOffset{job="kafka-broker"}  # Write position
kafka_raft_Replica_LogHighWatermark{job="kafka-broker"}  # Committed position

# KRaft Election Activity
sum(rate(kafka_raft_Quorum_ElectedLeaderChanges_total[5m]))  # Leader changes

# Message Flow
rate(kafka_server_BrokerTopicMetrics_BytesInPerSec_total[5m])  # Incoming
rate(kafka_server_BrokerTopicMetrics_MessagesInPerSec_total[5m])  # Message rate

# KRaft Quorum Latency
kafka_server_ClientId_Request_KafkaRequestHandler_totalTimeMs  # Request latency
```

### Refresh Interval
- **10 seconds** - Real-time monitoring of KRaft quorum operations

### Time Range
- **Default View**: Last 1 hour
- **Customizable**: Full time picker for historical analysis

---

## 2. KRaft Architecture & Monitoring

### 2.1 KRaft Role Distribution
In KRaft mode, brokers have dual roles:

**Controller + Broker (Combined Node)**
- Handles metadata management via Raft consensus
- Manages partition leadership elections
- Stores metadata in `__cluster_metadata` topic
- Processes client produce/consume requests

### 2.2 Quorum Mechanics
```
Cluster Size: 3 brokers
├─ Broker 1 (Controller, Leader) - Quorum Member
├─ Broker 2 (Controller)          - Quorum Member  
└─ Broker 3 (Controller)          - Quorum Member

Metadata Operations Quorum: 3/3 (unanimous)
Message Replication Quorum: 2/3 (majority)
```

### 2.3 Critical KRaft Metrics Explained

**KRaft Log End Offset**
- Highest offset written by leader
- Increases as metadata changes occur (broker joins, topic creation, etc.)

**KRaft High Water Mark**
- Offset committed across quorum majority
- Lag between Log End Offset and HWM indicates replication delays

**KRaft Leader Election Rate**
- Should be 0 during normal operations
- Spikes indicate network instability or broker failures
- Multiple elections suggest quorum health issues

**KRaft Uncommitted Records**
- Records awaiting quorum confirmation
- Should remain near 0
- Growing indicates write pressure or quorum lag

---

## 3. Implementation Requirements

### 3.1 Kafka Configuration for KRaft

Required broker properties in `server.properties`:

```properties
# KRaft Cluster Setup
process.roles=broker,controller
node.id=1
controller.quorum.voters=1@kafka-broker-1:9093,2@kafka-broker-2:9093,3@kafka-broker-3:9093
controller.listener.names=CONTROLLER
inter.broker.listener.name=BROKER

# Advertised Listeners
listeners=PLAINTEXT://kafka-broker-1:9092,CONTROLLER://kafka-broker-1:9093
advertised.listeners=PLAINTEXT://kafka-broker-1:9092

# KRaft Log Configuration
log.dirs=/var/kafka-logs
metadata.log.dir=/var/kafka-logs/__cluster_metadata-partition
metadata.max.retention.ms=604800000  # 7 days
metadata.max.retention.bytes=104857600  # 100 MB
```

### 3.2 Prometheus Configuration

Ensure scrape configs include all three brokers:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'kafka-broker'
    static_configs:
      - targets:
          - 'kafka-broker-1:9999'  # JMX exporter port
          - 'kafka-broker-2:9999'
          - 'kafka-broker-3:9999'
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '([^:]+)(?::\d+)?'
        replacement: '${1}'

  - job_name: 'node-exporter'
    static_configs:
      - targets:
          - 'kafka-broker-1:9100'
          - 'kafka-broker-2:9100'
          - 'kafka-broker-3:9100'
```

### 3.3 JMX Exporter Configuration

Configure JMX exporter on all brokers (port 9999):

```bash
# In docker-compose or startup script
KAFKA_JMX_PORT=9999
KAFKA_JMX_HOSTNAME=kafka-broker-1
```

### 3.4 Grafana Provisioning

The dashboard is deployed via:

```
/etc/grafana/provisioning/dashboards/ansible/kafka_kraft_dashboard.json
```

---

## 4. Recommended Alert Rules for KRaft

```yaml
groups:
  - name: kafka-kraft
    interval: 30s
    rules:
      # Critical: No KRaft Leader
      - alert: KRaftNoLeader
        expr: count(kafka_raft_Quorum_Leader{job="kafka-broker"} > 0) == 0
        for: 1m
        annotations:
          summary: "No KRaft leader elected"
          description: "KRaft quorum has no elected leader. Cluster metadata is unavailable."
      
      # Critical: Quorum Broken
      - alert: KRaftQuorumBroken
        expr: count(kafka_raft_Quorum_State{job="kafka-broker"}) < 2
        for: 2m
        annotations:
          summary: "KRaft quorum is broken"
          description: "Fewer than 2 brokers in quorum. Cluster may go down."
      
      # Warning: Metadata Replication Lag
      - alert: KRaftMetadataReplicationLag
        expr: |
          (kafka_raft_Replica_LogEndOffset{job="kafka-broker"} -
           kafka_raft_Replica_LogHighWatermark{job="kafka-broker"}) > 100
        for: 5m
        annotations:
          summary: "KRaft metadata replication lag detected"
          description: "High replication lag in metadata quorum"
      
      # Warning: Frequent Leader Elections
      - alert: KRaftFrequentElections
        expr: sum(rate(kafka_raft_Quorum_ElectedLeaderChanges_total[5m])) > 0.1
        for: 5m
        annotations:
          summary: "Frequent KRaft leader elections"
          description: "More than 6 leader elections per minute. Check network stability."
      
      # Critical: Under Replicated Partitions
      - alert: UnderReplicatedPartitions
        expr: sum(kafka_server_ReplicaManager_UnderReplicatedPartitions) > 0
        for: 5m
        annotations:
          summary: "Under replicated partitions detected"
          description: "{{ $value }} partitions are under-replicated"
      
      # Critical: Broker Down
      - alert: KafkaBrokerDown
        expr: count(kafka_server_BrokerTopicMetrics_BytesInPerSec_total{job="kafka-broker"}) < 3
        for: 1m
        annotations:
          summary: "Kafka broker is down"
          description: "Fewer than 3 brokers responding"
      
      # Warning: High Disk Usage
      - alert: KafkaHighDiskUsage
        expr: |
          (1 - (node_filesystem_avail_bytes{job="kafka-broker"} / 
                node_filesystem_size_bytes{job="kafka-broker"})) > 0.8
        for: 10m
        annotations:
          summary: "High disk usage on Kafka broker"
          description: "Disk usage exceeds 80% on {{ $labels.instance }}"
      
      # Warning: High Memory Usage
      - alert: KafkaHighMemoryUsage
        expr: |
          (1 - (node_memory_MemAvailable_bytes{job="kafka-broker"} /
                node_memory_MemTotal_bytes{job="kafka-broker"})) > 0.85
        for: 5m
        annotations:
          summary: "High memory usage on Kafka broker"
          description: "Memory usage exceeds 85% on {{ $labels.instance }}"
      
      # Warning: High CPU Usage
      - alert: KafkaHighCPUUsage
        expr: |
          (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle", job="kafka-broker"}[5m]))) > 0.8
        for: 5m
        annotations:
          summary: "High CPU usage on Kafka broker"
          description: "CPU usage exceeds 80% on {{ $labels.instance }}"
```

---

## 5. KRaft Mode Dashboard Usage

### 5.1 Quick Health Checks
1. **Verify KRaft Leader**: Should show "1" in top row
2. **Check Quorum Size**: Should match cluster size (typically 3)
3. **Monitor URP**: Should be "0" under normal conditions
4. **Brokers Online**: Should equal total broker count

### 5.2 Performance Analysis
- **Byte Rate**: Monitor for expected throughput patterns
- **Message Rate**: Check for producer/consumer imbalances
- **Latency**: Should remain < 10ms for quorum operations

### 5.3 Troubleshooting Scenarios

**Scenario 1: Leader Election Happening**
- Check "KRaft Leader Election Rate" graph
- Verify "KRaft Leaders" count = 1
- Investigate network connectivity between brokers

**Scenario 2: Under-Replicated Partitions**
- Check if specific brokers are down
- Verify disk space on all brokers
- Check "KRaft High Water Mark" lag

**Scenario 3: Metadata Replication Lag**
- Check "KRaft Uncommitted Records" - should be near 0
- Verify quorum latency < 10ms
- Check broker JVM GC pauses

**Scenario 4: Broker Performance Degradation**
- Check JVM metrics (memory, GC)
- Check CPU and disk usage
- Verify network connectivity

---

## 6. KRaft-Specific Tuning

### 6.1 Log Configuration
```properties
# Metadata log retention (7 days recommended)
metadata.max.retention.ms=604800000

# Metadata log size (100 MB for small clusters)
metadata.max.retention.bytes=104857600

# Faster metadata propagation
metadata.flush.interval.ms=5000
```

### 6.2 Quorum Parameters
```properties
# Election timeout (default 10s)
election.backoff.max.ms=10000

# Graceful shutdown timeout
quorum.request.timeout.ms=10000
```

### 6.3 Monitoring Adjustments
- **Scrape Interval**: 15s recommended (not more than 30s)
- **Evaluation Interval**: 15s for consistent alerting
- **Retention**: Minimum 7 days for historical analysis

---

## 7. File Locations

```
ansible/
├── files/
│   └── dashboards/
│       ├── kafka_kraft_dashboard.json       # Main KRaft monitoring
│       └── node_exporter_dashboard.json     # System metrics (optional)
├── roles/
│   └── monitoring/
│       └── prometheus_grafana/
│           ├── tasks/
│           │   └── main.yml
│           └── templates/
│               └── prometheus.yml.j2
└── playbooks/
    └── deploy_monitoring_playbook.yml
```

---

## 8. Deployment

### 8.1 Via Ansible
```bash
# Deploy complete monitoring stack
ansible-playbook ansible/playbooks/deploy_monitoring_playbook.yml

# Verify dashboard provisioning
curl http://grafana-host:3000/api/dashboards/uid/kafka-cluster-kraft-monitoring
```

### 8.2 Manual Import
1. Access Grafana (http://grafana:3000)
2. Home → Dashboards → Import
3. Upload `kafka_kraft_dashboard.json`
4. Select Prometheus datasource
5. Save

---

## 9. KRaft Migration Path (if upgrading from ZK)

### Pre-Migration Checklist
- [ ] Kafka brokers running 3.0+
- [ ] All brokers have consistent broker.id configuration
- [ ] New controller quorum voters configured
- [ ] Network ports 9093 open for CONTROLLER listener
- [ ] Monitoring Prometheus updated

### Migration Steps
1. Add KRaft properties to broker config
2. Run migration tool: `kafka-migration.sh`
3. Verify metadata replication
4. Monitor KRaft quorum stability (check dashboard)
5. Retire ZooKeeper cluster

### Post-Migration Verification
- [ ] All brokers show in quorum
- [ ] No leader elections in last 5 minutes
- [ ] Message throughput normal
- [ ] No under-replicated partitions
- [ ] Log End Offset == High Water Mark

---

## 10. Version Information

- **Kafka**: 3.0+ (KRaft GA from 3.3)
- **Grafana**: 8.0+
- **Prometheus**: 2.30+
- **Schema Version**: 38 (latest JSON dashboard format)
- **Dashboard Version**: 1 (KRaft optimized)

---

## 11. Appendix: KRaft-Specific Metric Glossary

| Metric | Type | Description | KRaft Context |
|--------|------|---|---|
| `kafka_raft_Quorum_Leader` | Gauge | Current leader broker | Should be 1 |
| `kafka_raft_Quorum_State` | Gauge | Membership in quorum | Count = cluster size |
| `kafka_raft_Replica_LogEndOffset` | Gauge | Highest written offset | Leader only |
| `kafka_raft_Replica_LogHighWatermark` | Gauge | Replicated offset | Should lag LEO by <100 |
| `kafka_raft_Quorum_ElectedLeaderChanges_total` | Counter | Leader election events | Should stay at 0 |
| `kafka_raft_Quorum_RequestLatency` | Gauge | Metadata request latency (ms) | Target: <10ms |
| `kafka_raft_Replica_UncommittedRecords` | Gauge | Pending commit records | Should be near 0 |
| `kafka_server_ReplicaManager_LeaderCount` | Gauge | Leader partitions on broker | Distributes across cluster |
| `kafka_server_ReplicaManager_UnderReplicatedPartitions` | Gauge | URP count | Should be 0 |
| `kafka_server_BrokerTopicMetrics_BytesInPerSec_total` | Counter | Total bytes received | Throughput metric |
| `kafka_server_BrokerTopicMetrics_MessagesInPerSec_total` | Counter | Total messages received | Message rate metric |

---

## 12. Support & Troubleshooting

### Common Issues

**Issue**: KRaft leader not elected
```
Solution: 
1. Check broker logs for election errors
2. Verify controller.quorum.voters configuration
3. Check network connectivity on port 9093
4. Ensure clock skew < 1s across brokers
```

**Issue**: Metadata replication lag
```
Solution:
1. Check broker CPU and disk I/O
2. Increase metadata.log.segment.bytes if many small writes
3. Verify network bandwidth between brokers
4. Check JVM GC pauses
```

**Issue**: Dashboard shows no data
```
Solution:
1. Verify JMX exporter running: curl http://broker:9999/metrics
2. Check Prometheus targets: http://prometheus:9090/targets
3. Verify metric names in queries
4. Check Grafana datasource connectivity
```

