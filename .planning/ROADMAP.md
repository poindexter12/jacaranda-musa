# Roadmap: Musa Project

## Milestones

- **v1.17 Post-Split Validation & Hardening** - Phases 1-5 (superseded / partial)
- **v2.1 SSH Cert Provisioning & Resource Registration** - Phases 7-8 (in progress)
- **v2.0 Multi-Node HA** - Phases 6, 9-12 (planned)

## Overview

Transform the single-node Twenty CRM deployment into a production-ready, highly available architecture across 3 Proxmox nodes (joseph, everette, maxwell). v2.1 replaces CA-based SSH auth with per-environment key pairs, formalizes resource allocations in the network registry, and provisions the 3-node test LXC infrastructure. This unblocks the v2.0 HA work (PostgreSQL Patroni, Redis Sentinel, dual app instances, backups, failover validation).

## Phases

<details>
<summary>v1.17 Post-Split Validation & Hardening (Phases 1-5) - SUPERSEDED</summary>

See `.planning/MILESTONES.md` for v1.17 summary.

Phase 5 consolidated Phases 1-4. Shipped: external URL validation, GHCR image pinning, health check tightening, domain consolidation, rollback procedure, secrets documentation.

</details>

### v2.1 SSH Cert Provisioning & Resource Registration

**Milestone Goal:** Replace CA-based SSH auth with per-environment SSH key pairs and formalize resource allocations via registry, unblocking immediate infrastructure provisioning.

- [x] **Phase 7: Resource Registration & Terraform Prep** - Formalize VMID/IP allocations in registry and update Terraform to skip CA cert signing (completed 2026-05-02)
- [ ] **Phase 8: LXC Provisioning & Validation** - Provision 3-node test LXCs and validate SSH connectivity

### v2.0 Multi-Node HA (Planned)

**Milestone Goal:** Highly available Twenty CRM that automatically recovers from single-node failures with minimal data loss and zero manual intervention.

- [~] **Phase 6: Multi-Node Infrastructure** - 3 LXCs across 3 Proxmox nodes with multi-group inventory (code complete 2026-04-28; verification checkpoint PENDING)
- [ ] **Phase 9: PostgreSQL HA** - Patroni + etcd cluster with streaming replication and data migration
- [ ] **Phase 10: Redis HA & Backup Strategy** - Redis Sentinel failover and pgBackRest PITR + GFS rotation
- [ ] **Phase 11: Application HA & Failover Validation** - Dual app instances, dual tunnels, and comprehensive failover tests
- [ ] **Phase 12: Production Environment** - Same HA topology with production-sized resources

## Phase Details

### Phase 6: Multi-Node Infrastructure
**Goal**: 3 LXC containers are provisioned across all Proxmox nodes with correct resource allocation and Ansible can target each node by role
**Depends on**: Nothing (foundation phase for v2.0)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04
**Success Criteria** (what must be TRUE):
  1. `tofu apply` creates 3 LXC containers (one per Proxmox node: joseph, everette, maxwell) with correct VMIDs
  2. Ansible inventory is auto-generated with groups for etcd_nodes, patroni_nodes, app_nodes, and backup_nodes
  3. Per-node resource allocation (cores, memory, disk) is configurable via Terraform variables and differs between test and prod
  4. All 3 LXCs are reachable via SSH and Docker is functional inside each (test environment operational)
**Plans:** 2/2 plans complete (verification checkpoint pending)

**Note:** Success Criterion 4 is unconfirmed — human verification of 3-LXC SSH + Docker has not been run. Phase 7 must not begin until `just test::verify` and `just test::validate` pass on all 3 hosts.

Plans:
- [x] 06-01-PLAN.md — Terraform multi-node infrastructure (3 LXCs, dual NIC, per-instance resources, custom multi-group inventory)
- [~] 06-02-PLAN.md — Justfile multi-host recipes (complete); infrastructure verification checkpoint SKIPPED (pending)

### Phase 7: Resource Registration & Terraform Prep
**Goal**: All musa resource allocations are formalized in the network registry and Terraform LXC module calls no longer depend on CA cert signing
**Depends on**: Phase 6 (code complete; uses existing Terraform multi-node configuration)
**Requirements**: REG-01, REG-02, REG-03, PROV-01
**Success Criteria** (what must be TRUE):
  1. Registry contains VMID entries for 1190 (joseph), 1191 (everette), 1192 (maxwell) attributed to musa service
  2. Registry contains mgmt VLAN IP entries for 192.168.5.190, .191, .192 and transfer VLAN IP entries for 192.168.11.190, .191, .192
  3. `tofu plan` for test environment completes without referencing CA cert signing module or variables
  4. No CA-related variables, module calls, or outputs remain in musa Terraform configuration
**Plans:** 2/2 plans complete

Plans:
- [x] 07-01-PLAN.md — Registry VMID formalization (add vmid/node fields to musa allocations in jacaranda-inventory)
- [x] 07-02-PLAN.md — Terraform CA removal (remove ssh_user_ca_pubkey from musa Terraform, bump shared module to v1.5.0)

### Phase 8: LXC Provisioning & Validation
**Goal**: 3 test LXC containers are running on Proxmox and accessible via SSH using the per-environment key pair
**Depends on**: Phase 7 (Terraform prep must be complete before apply)
**Requirements**: PROV-02, PROV-03
**Success Criteria** (what must be TRUE):
  1. `tofu apply` for test environment succeeds, creating 3 LXC containers (VMIDs 1190, 1191, 1192)
  2. `ssh root@test.app1.app.musa.lan` connects successfully using the musa-test key pair (identity routed via SSH config)
  3. SSH connectivity is confirmed to all 3 hosts (test.app1.app.musa, test.app2.app.musa, test.bak.backup.musa)
  4. Docker is functional inside each LXC (`docker ps` runs without error on all 3 hosts)
**Plans**: 1 plan

Plans:
- [ ] 08-01-PLAN.md — Provision 3-node test LXCs and validate SSH + Docker connectivity

### Phase 9: PostgreSQL HA
**Goal**: A 3-node Patroni PostgreSQL cluster with automatic failover is running, and existing data has been migrated from the single-node deployment without loss
**Depends on**: Phase 8
**Requirements**: PGHA-01, PGHA-02, PGHA-03, PGHA-04, PGHA-05, PGHA-06, PGHA-07
**Success Criteria** (what must be TRUE):
  1. etcd cluster is healthy across 3 nodes (`etcdctl endpoint health` reports all members healthy)
  2. Patroni cluster shows 1 leader + 2 replicas with streaming replication (`patronictl list` confirms)
  3. Killing the primary node triggers automatic failover to a replica within 60 seconds (new leader elected, writes resume)
  4. Patroni REST API responds on each node (health checks functional)
  5. Existing Twenty CRM data from single-node deployment is present in the cluster (migration verified, no data loss)
**Plans**: TBD

Plans:
- [ ] 09-01: TBD
- [ ] 09-02: TBD
- [ ] 09-03: TBD

### Phase 10: Redis HA & Backup Strategy
**Goal**: Redis has automatic failover via Sentinel, and PostgreSQL has continuous WAL archiving (PITR) plus GFS rotation backups
**Depends on**: Phase 9
**Requirements**: RDHA-01, RDHA-02, RDHA-03, RDHA-04, BKUP-01, BKUP-02, BKUP-03, BKUP-04, BKUP-05, BKUP-06
**Success Criteria** (what must be TRUE):
  1. Redis Sentinel reports 1 master + 2 replicas with quorum=2; killing the master triggers automatic promotion of a replica
  2. Twenty CRM connects to Redis via Sentinel discovery (not direct host:port) and survives a Redis failover without restart
  3. pgBackRest continuous WAL archiving is active; `pgbackrest info` shows a valid stanza with recent WAL segments
  4. Scheduled full (weekly) and differential (daily) pgBackRest backups execute from the standby node (not the primary)
  5. pg_dump GFS rotation produces daily/7d, weekly/4w, monthly/12mo snapshots on the backup node
**Plans**: TBD

Plans:
- [ ] 10-01: TBD
- [ ] 10-02: TBD
- [ ] 10-03: TBD

### Phase 11: Application HA & Failover Validation
**Goal**: Twenty CRM runs on 2 app nodes with dual Cloudflare Tunnel ingress, and all HA components have tested failover procedures
**Depends on**: Phase 10
**Requirements**: APHA-01, APHA-02, APHA-03, APHA-04, APHA-05, VALD-01, VALD-02, VALD-03, VALD-04
**Success Criteria** (what must be TRUE):
  1. Twenty CRM server + worker are running on 2 nodes, each with SWAG reverse proxy, and both respond to health checks
  2. Dual Cloudflare Tunnel (same token on both app nodes) provides ingress failover -- killing one tunnel still routes traffic to the other
  3. `just test::validate` checks health of all HA components: etcd cluster, Patroni leader/replicas, Sentinel quorum, and both app instances
  4. Manual failover test recipes exist and pass: PG failover (kill primary, verify promotion), Redis failover (kill master, verify Sentinel promotion), app failover (kill node, verify traffic reroute)
  5. Single-node failure (any one of the 3 nodes down) does not disrupt Twenty CRM service (end-to-end validated)
**Plans**: TBD

Plans:
- [ ] 11-01: TBD
- [ ] 11-02: TBD
- [ ] 11-03: TBD

### Phase 12: Production Environment
**Goal**: The same HA topology is deployed to production with production-sized resources
**Depends on**: Phase 11
**Requirements**: INFRA-05
**Success Criteria** (what must be TRUE):
  1. Production 3-node HA topology is deployed with larger resource allocation (cores, memory, disk) than test
  2. All HA components (etcd, Patroni, Sentinel, dual app, dual tunnel) are operational in production
  3. `just prod::validate` confirms production cluster health (same checks as test::validate)
**Plans**: TBD

Plans:
- [ ] 12-01: TBD
- [ ] 12-02: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 7 -> 8 (v2.1), then 6-verify -> 9 -> 10 -> 11 -> 12 (v2.0)

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 6. Multi-Node Infrastructure | v2.0 | 2/2 | Verify pending | 2026-04-28 (code) |
| 7. Resource Registration & Terraform Prep | v2.1 | 2/2 | Complete | 2026-05-02 |
| 8. LXC Provisioning & Validation | v2.1 | 0/TBD | Not started | - |
| 9. PostgreSQL HA | v2.0 | 0/TBD | Not started | - |
| 10. Redis HA & Backup Strategy | v2.0 | 0/TBD | Not started | - |
| 11. Application HA & Failover Validation | v2.0 | 0/TBD | Not started | - |
| 12. Production Environment | v2.0 | 0/TBD | Not started | - |
