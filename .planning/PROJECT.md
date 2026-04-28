# Musa Project — Twenty CRM Service

## What This Is

Infrastructure-as-Code repository for deploying Twenty CRM on Proxmox with high availability. Multi-node architecture: Patroni PostgreSQL cluster, Redis Sentinel, dual Twenty CRM app instances with Cloudflare Tunnel failover, and comprehensive backup strategy (pgBackRest PITR + GFS rotation). Deployed across 3 Proxmox nodes (joseph, everette, maxwell).

## Core Value

A production-grade, highly available Twenty CRM deployment that automatically recovers from single-node failures with minimal data loss (seconds via PITR) and zero manual intervention.

## Current Milestone: v2.0 Multi-Node HA

**Goal:** Transform single-node test deployment into a production-ready, highly available architecture across 3 Proxmox nodes with automated failover for PostgreSQL, Redis, and application layers.

**Target features:**
- Patroni PostgreSQL cluster (3-node with etcd consensus)
- Redis Sentinel HA (2 data nodes + 3 sentinels)
- Dual Twenty CRM app instances
- Dual Cloudflare Tunnel ingress (both app nodes)
- pgBackRest PITR (continuous WAL archiving)
- GFS backup rotation (hourly/daily/weekly/monthly)
- Test environment first (3-node, same topology as prod)
- Production environment (3-node, larger resources)

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ LXC container provisioning via Terraform/OpenTofu on Proxmox — v1.17
- ✓ Docker-in-LXC with nesting enabled — v1.17
- ✓ 9-container Docker Compose stack (SWAG, Twenty server/worker, PostgreSQL, Redis, backup, rollup, webhook receiver/worker) — v1.17
- ✓ SWAG reverse proxy with Let's Encrypt SSL via Cloudflare DNS-01 challenge — v1.17
- ✓ Cloudflare Tunnel for external access without port forwarding — v1.17
- ✓ 1Password secret injection at deploy time via justfile recipes — v1.17
- ✓ Ansible role with idempotent tasks, health checks, and handler-based restarts — v1.17
- ✓ Shared library submodule (jacaranda-shared-libs v1.4.0) for Terraform modules and justfile utilities — v1.17
- ✓ GHCR image pinning with configurable version tags — v1.17
- ✓ Domain consolidation to single source of truth — v1.17
- ✓ Rollback procedure via .bak snapshots — v1.17
- ✓ Health check tightening (10s interval, 5 retries, curl timeouts) — v1.17

### Active

<!-- Current scope — what this milestone delivers. -->

- [ ] 3-node Patroni PostgreSQL cluster with automatic failover
- [ ] etcd consensus cluster (3 nodes)
- [ ] Redis Sentinel HA (2 data + 3 sentinel)
- [ ] Dual Twenty CRM app instances across 2 nodes
- [ ] Dual Cloudflare Tunnel ingress (both app nodes, Cloudflare load-balances)
- [ ] pgBackRest PITR with continuous WAL archiving
- [ ] GFS backup rotation: hourly/24h, daily/7d, weekly/4w, monthly/12mo
- [ ] Terraform multi-node LXC provisioning (3 instances per environment)
- [ ] Test environment: 3-node HA topology (smaller resources)
- [ ] Production environment: 3-node HA topology (production resources)
- [ ] Failover validation (PG, Redis, app layer)

### Out of Scope

- Centralized log aggregation (ELK/Loki) — address in future milestone
- Docker Swarm — staying with Docker Compose per node
- Active-active PostgreSQL (multi-primary) — Patroni uses single-primary with auto-failover
- Redis Cluster (sharding) — Sentinel sufficient for CRM workload
- Citus distributed PostgreSQL — unnecessary complexity for CRM scale
- Automated scaling — fixed 3-node topology
- Blue-green deployment — failover handles availability

## Context

v1.17 established the single-node deployment pattern (Docker-in-LXC on joseph). The Docker Compose stack, SWAG reverse proxy, Cloudflare Tunnel, and 1Password secrets flow are proven. This milestone transforms the architecture from single-node to multi-node HA while preserving the Docker-in-LXC pattern (1 LXC per Proxmox node).

Proxmox cluster nodes: joseph, everette, maxwell. Each node gets one LXC running all services for that node via Docker Compose.

Current test single-node LXC (VMID 1180 on joseph) will be replaced by the 3-node topology.

## Constraints

- **Nodes**: 3 Proxmox nodes (joseph, everette, maxwell)
- **Pattern**: Docker-in-LXC (1 LXC per node, Docker Compose inside)
- **Secrets**: 1Password CLI via op-read script
- **Network**: Cloudflare Tunnel for external access (no port forwarding)
- **Dependencies**: Shared-libs submodule pinned to v1.4.0
- **Storage**: Ceph across cluster (via base-infra module)
- **Consensus**: etcd requires 3 nodes for quorum (maps to 3 Proxmox nodes)
- **Sentinel**: Redis Sentinel requires 3 sentinels for quorum

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Docker-in-LXC pattern validated | Proven in v1.17, Docker handles internal networking | ✓ Good |
| SWAG + Cloudflare Tunnel approach | External access without port forwarding | ✓ Good |
| 1 LXC per node (not separate LXCs per service) | Simpler management, Docker handles internal networking, HA is across nodes | — Pending |
| Patroni for PG HA (not manual replication) | Automatic failover, proven with PostgreSQL | — Pending |
| Redis Sentinel (not Redis Cluster) | CRM workload doesn't need sharding, just failover | — Pending |
| pgBackRest for PITR (not Barman) | Better community support, faster restores, built-in compression | — Pending |
| Dual Cloudflare Tunnel | True HA for ingress, Cloudflare load-balances between nodes | — Pending |
| Test first, then prod | Validate HA topology with smaller resources before production | — Pending |
| GFS + PITR (both) | Defense in depth: PITR for surgical recovery, GFS for portable snapshots | — Pending |

---
*Last updated: 2026-04-27 after v2.0 milestone initialization*
