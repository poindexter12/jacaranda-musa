# Requirements: Musa Project

**Defined:** 2026-05-02
**Core Value:** A production-grade, highly available Twenty CRM deployment that automatically recovers from single-node failures with minimal data loss and zero manual intervention.

## v2.1 Requirements

Requirements for SSH cert provisioning and resource registration milestone.

### Registry

- [ ] **REG-01**: Formalize VMID allocations (1190, 1191, 1192) for musa service in registry
- [ ] **REG-02**: Formalize mgmt VLAN IP allocations (192.168.5.190, 192.168.5.191, 192.168.5.192) in registry
- [ ] **REG-03**: Formalize transfer VLAN IP allocations (192.168.11.190, 192.168.11.191, 192.168.11.192) in registry

### Provisioning

- [ ] **PROV-01**: Update Terraform LXC module calls to skip CA cert signing
- [ ] **PROV-02**: Provision 3-node test LXC cluster with new SSH auth approach
- [ ] **PROV-03**: Validate SSH connectivity to all 3 test LXCs using per-environment key

## v2.0 Requirements (Carried Forward)

Previous milestone requirements carried forward for future phases.

### Infrastructure (v2.0)

- [x] **INFRA-01**: 3 LXC containers provisioned across joseph, everette, maxwell via Terraform
- [x] **INFRA-02**: Multi-group Ansible inventory generated (etcd_nodes, patroni_nodes, app_nodes, backup_nodes)
- [x] **INFRA-03**: Per-node resource allocation (cores, memory, disk) configurable via Terraform variables
- [x] **INFRA-04**: Test environment: 3-node HA topology deployed and functional
- [ ] **INFRA-05**: Production environment: 3-node HA topology with production-sized resources

### PostgreSQL HA (v2.0)

- [ ] **PGHA-01**: 3-node Patroni cluster with automatic leader election via etcd
- [ ] **PGHA-02**: Automatic failover when primary node fails (< 60s recovery)
- [ ] **PGHA-03**: Streaming replication to 2 standby nodes
- [ ] **PGHA-04**: etcd 3-node consensus cluster running on all nodes
- [ ] **PGHA-05**: Patroni REST API accessible for health checks on each node
- [ ] **PGHA-06**: Custom Patroni bootstrap from pgBackRest for fast replica rebuilds
- [ ] **PGHA-07**: Existing single-node PG data migrated to Patroni cluster without data loss

### Redis HA (v2.0)

- [ ] **RDHA-01**: Redis Sentinel with 3 sentinels across all nodes (quorum=2)
- [ ] **RDHA-02**: 1 Redis master + 2 replicas with automatic failover
- [ ] **RDHA-03**: Sentinel announce-ip configured for Docker cross-node discovery
- [ ] **RDHA-04**: Twenty CRM configured with Sentinel-aware Redis client

### Backup & Recovery (v2.0)

- [ ] **BKUP-01**: pgBackRest continuous WAL archiving for PITR
- [ ] **BKUP-02**: Scheduled full backups (weekly) and differential backups (daily) via pgBackRest
- [ ] **BKUP-03**: pgBackRest repo host on dedicated backup node
- [ ] **BKUP-04**: Backup from standby node (reduce primary load)
- [ ] **BKUP-05**: pg_dump GFS rotation: daily/7d, weekly/4w, monthly/12mo
- [ ] **BKUP-06**: Point-in-time restore procedure documented and tested

### Application HA (v2.0)

- [ ] **APHA-01**: Twenty CRM server + worker running on 2 nodes
- [ ] **APHA-02**: Dual Cloudflare Tunnel (same token, both app nodes) for ingress failover
- [ ] **APHA-03**: SWAG reverse proxy on each app node
- [ ] **APHA-04**: Health endpoint monitoring via Patroni REST API integrated into validate recipes
- [ ] **APHA-05**: `just test::validate` checks all HA component health (etcd, Patroni, Sentinel, app)

### Validation (v2.0)

- [ ] **VALD-01**: Manual failover test recipe for PostgreSQL (kill primary, verify promotion)
- [ ] **VALD-02**: Manual failover test recipe for Redis (kill master, verify Sentinel promotion)
- [ ] **VALD-03**: Manual failover test recipe for app/tunnel (kill app node, verify traffic reroute)
- [ ] **VALD-04**: End-to-end HA validation: single node failure doesn't disrupt service

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
| SSH key generation | User handles manually, stores in 1Password |
| SSH config setup | User configures IdentityFile routing |
| Prod environment provisioning | Test first, prod in later milestone |
| Full Twenty CRM stack deploy | Separate milestone after infra validated |
| Ansible role updates | Not needed for provisioning-only scope |
| CA infrastructure | Deliberately replaced by per-environment keys |
| Docker Swarm / Kubernetes | Overkill for 3-node homelab |
| Redis Cluster (sharding) | Sentinel sufficient for CRM workload |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| REG-01 | — | Pending |
| REG-02 | — | Pending |
| REG-03 | — | Pending |
| PROV-01 | — | Pending |
| PROV-02 | — | Pending |
| PROV-03 | — | Pending |

**Coverage:**
- v2.1 requirements: 6 total
- Mapped to phases: 0
- Unmapped: 6

---
*Requirements defined: 2026-05-02*
*Last updated: 2026-05-02 after initial definition*
