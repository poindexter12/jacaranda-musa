# Requirements: Musa Project

**Defined:** 2026-04-28
**Core Value:** A production-grade, highly available Twenty CRM deployment that automatically recovers from single-node failures with minimal data loss and zero manual intervention

## v2 Requirements

Requirements for Multi-Node HA milestone. Each maps to roadmap phases.

### Infrastructure

- [ ] **INFRA-01**: 3 LXC containers provisioned across joseph, everette, maxwell via Terraform
- [ ] **INFRA-02**: Multi-group Ansible inventory generated (etcd_nodes, patroni_nodes, app_nodes, backup_nodes)
- [ ] **INFRA-03**: Per-node resource allocation (cores, memory, disk) configurable via Terraform variables
- [ ] **INFRA-04**: Test environment: 3-node HA topology deployed and functional
- [ ] **INFRA-05**: Production environment: 3-node HA topology with production-sized resources

### PostgreSQL HA

- [ ] **PGHA-01**: 3-node Patroni cluster with automatic leader election via etcd
- [ ] **PGHA-02**: Automatic failover when primary node fails (< 60s recovery)
- [ ] **PGHA-03**: Streaming replication to 2 standby nodes
- [ ] **PGHA-04**: etcd 3-node consensus cluster running on all nodes
- [ ] **PGHA-05**: Patroni REST API accessible for health checks on each node
- [ ] **PGHA-06**: Custom Patroni bootstrap from pgBackRest for fast replica rebuilds
- [ ] **PGHA-07**: Existing single-node PG data migrated to Patroni cluster without data loss

### Redis HA

- [ ] **RDHA-01**: Redis Sentinel with 3 sentinels across all nodes (quorum=2)
- [ ] **RDHA-02**: 1 Redis master + 2 replicas with automatic failover
- [ ] **RDHA-03**: Sentinel announce-ip configured for Docker cross-node discovery
- [ ] **RDHA-04**: Twenty CRM configured with Sentinel-aware Redis client

### Backup & Recovery

- [ ] **BKUP-01**: pgBackRest continuous WAL archiving for PITR
- [ ] **BKUP-02**: Scheduled full backups (weekly) and differential backups (daily) via pgBackRest
- [ ] **BKUP-03**: pgBackRest repo host on dedicated backup node
- [ ] **BKUP-04**: Backup from standby node (reduce primary load)
- [ ] **BKUP-05**: pg_dump GFS rotation: daily/7d, weekly/4w, monthly/12mo
- [ ] **BKUP-06**: Point-in-time restore procedure documented and tested

### Application HA

- [ ] **APHA-01**: Twenty CRM server + worker running on 2 nodes
- [ ] **APHA-02**: Dual Cloudflare Tunnel (same token, both app nodes) for ingress failover
- [ ] **APHA-03**: SWAG reverse proxy on each app node
- [ ] **APHA-04**: Health endpoint monitoring via Patroni REST API integrated into validate recipes
- [ ] **APHA-05**: `just test::validate` checks all HA component health (etcd, Patroni, Sentinel, app)

### Validation

- [ ] **VALD-01**: Manual failover test recipe for PostgreSQL (kill primary, verify promotion)
- [ ] **VALD-02**: Manual failover test recipe for Redis (kill master, verify Sentinel promotion)
- [ ] **VALD-03**: Manual failover test recipe for app/tunnel (kill app node, verify traffic reroute)
- [ ] **VALD-04**: End-to-end HA validation: single node failure doesn't disrupt service

## v1 Requirements (Completed / Partial)

Previous milestone requirements. Marked with completion status.

### Pipeline

- [x] **PIPE-03**: `just test::validate` confirms all 9 containers healthy
- [x] **PIPE-04**: `just check-secrets` passes for all 7 1Password items
- [ ] **PIPE-01**: `just test::full` runs end-to-end without errors (not validated)
- [ ] **PIPE-02**: `just test::deploy` re-deploys idempotently (not validated)

### Image Pinning

- [x] **IMGP-01**: Backup container pinned to specific version tag
- [x] **IMGP-02**: Rollup container pinned to specific version tag
- [x] **IMGP-03**: Webhook containers pinned to specific version tags

### Health Checks

- [x] **HLTH-01**: Docker Compose health checks: 10s interval, 5 retries max
- [x] **HLTH-03**: Ansible health check tasks include explicit curl timeouts
- [ ] **HLTH-02**: External URL check via Cloudflare Tunnel (deferred — superseded by APHA-05)

### Configuration

- [x] **CONF-01**: Domain references use single variable source
- [x] **CONF-02**: Rollback recipe exists
- [x] **CONF-03**: Secrets exposure documented

### Upgrade

- [ ] **UPGR-01**: Twenty CRM v1.18.0 (deferred — already running v1.18 manually)
- [ ] **UPGR-02**: Database migrations (completed manually)
- [ ] **UPGR-03**: External access post-upgrade (completed manually)

## Future Requirements

Deferred to future milestones.

### Monitoring

- **MNTR-01**: Backup failure alerts via webhook notification
- **MNTR-02**: Centralized log forwarding (syslog or Loki)
- **MNTR-03**: Redis memory usage monitoring
- **MNTR-04**: Patroni cluster health dashboard

### Automation

- **AUTO-01**: Automated failover validation playbook
- **AUTO-02**: Automated backup verification (restore test)
- **AUTO-03**: Rolling update automation with zero-downtime

## Out of Scope

| Feature | Reason |
|---------|--------|
| Docker Swarm / Kubernetes | Overkill for 3-node homelab; Docker Compose per node proven |
| Docker overlay networking | Direct VLAN networking between LXCs simpler and proven |
| Redis Cluster (sharding) | Sentinel sufficient for CRM workload |
| HAProxy for PG connection routing | Patroni handles failover; app reconnects directly |
| PgBouncer connection pooling | Not needed at CRM scale |
| Citus distributed PostgreSQL | Unnecessary complexity for CRM data volume |
| Consul / ZooKeeper | etcd is Patroni's primary target, less overhead |
| Synchronous replication | Higher write latency; async sufficient for CRM |
| Active-active PostgreSQL | Single-primary with auto-failover via Patroni |
| Centralized log aggregation | Future milestone |
| Automated scaling | Fixed 3-node topology |
| Blue-green deployment | Failover handles availability |

## Traceability

Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | TBD | Pending |
| INFRA-02 | TBD | Pending |
| INFRA-03 | TBD | Pending |
| INFRA-04 | TBD | Pending |
| INFRA-05 | TBD | Pending |
| PGHA-01 | TBD | Pending |
| PGHA-02 | TBD | Pending |
| PGHA-03 | TBD | Pending |
| PGHA-04 | TBD | Pending |
| PGHA-05 | TBD | Pending |
| PGHA-06 | TBD | Pending |
| PGHA-07 | TBD | Pending |
| RDHA-01 | TBD | Pending |
| RDHA-02 | TBD | Pending |
| RDHA-03 | TBD | Pending |
| RDHA-04 | TBD | Pending |
| BKUP-01 | TBD | Pending |
| BKUP-02 | TBD | Pending |
| BKUP-03 | TBD | Pending |
| BKUP-04 | TBD | Pending |
| BKUP-05 | TBD | Pending |
| BKUP-06 | TBD | Pending |
| APHA-01 | TBD | Pending |
| APHA-02 | TBD | Pending |
| APHA-03 | TBD | Pending |
| APHA-04 | TBD | Pending |
| APHA-05 | TBD | Pending |
| VALD-01 | TBD | Pending |
| VALD-02 | TBD | Pending |
| VALD-03 | TBD | Pending |
| VALD-04 | TBD | Pending |

**Coverage:**
- v2 requirements: 24 total
- Mapped to phases: 0
- Unmapped: 24 (pending roadmap creation)

---
*Requirements defined: 2026-04-28*
*Last updated: 2026-04-28 after milestone v2.0 definition*
