# Musa Project — Twenty CRM Service

## What This Is

Infrastructure-as-Code repository for deploying Twenty CRM on Proxmox with high availability. Multi-node architecture: Patroni PostgreSQL cluster, Redis Sentinel, dual Twenty CRM app instances with Cloudflare Tunnel failover, and comprehensive backup strategy (pgBackRest PITR + GFS rotation). Deployed across 3 Proxmox nodes (joseph, everette, maxwell).

## Core Value

A production-grade, highly available Twenty CRM deployment that automatically recovers from single-node failures with minimal data loss (seconds via PITR) and zero manual intervention.

## Current Milestone: v2.1 SSH Cert Provisioning & Resource Registration

**Goal:** Replace CA-based SSH auth with per-environment SSH key pairs and formalize resource allocations via registry, unblocking immediate infrastructure provisioning.

**Target features:**
- Per-environment SSH key pairs (test + prod), stored in 1Password
- SSH config identity routing for musa hosts
- Skip CA cert signing in LXC module (remove CA dependency)
- Formalize existing resource allocations (VMIDs 1190-1192, IPs .190-.192) via registry
- Provision 3-node test LXC infrastructure with new SSH auth
- Validate SSH connectivity to all provisioned LXCs

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

- [ ] SSH key pair for musa-test environment, stored in 1Password
- [ ] SSH key pair for musa-prod environment, stored in 1Password
- [ ] SSH config identity routing for musa host patterns
- [ ] LXC module calls skip CA cert signing (no CA dependency)
- [ ] Formalize existing allocations (VMIDs 1190-1192, IPs .190-.192) in registry
- [ ] Provision 3-node test LXC infrastructure with new SSH auth
- [ ] Validate SSH connectivity to all 3 test LXCs

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
## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-02 after v2.1 milestone initialization*
