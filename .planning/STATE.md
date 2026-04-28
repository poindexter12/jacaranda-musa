---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Multi-Node HA
status: defining_requirements
last_updated: "2026-04-27"
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-27)

**Core value:** A production-grade, highly available Twenty CRM deployment that automatically recovers from single-node failures
**Current focus:** Defining requirements for v2.0

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-04-27 — Milestone v2.0 started

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Docker-in-LXC pattern validated in v1.17 (proven approach)
- 1 LXC per Proxmox node, Docker Compose handles internal services
- Patroni + etcd for PG HA (automatic failover)
- Redis Sentinel for Redis HA (2 data + 3 sentinel)
- pgBackRest for PITR + GFS pg_dump for portable backups
- Dual Cloudflare Tunnel for true HA ingress
- Test environment first (3-node, same topology as prod)
- Proxmox nodes: joseph, everette, maxwell

### Carried from v1.17

- SWAG + Cloudflare Tunnel approach works for external access
- 1Password secret injection via op-read script is reliable
- Consolidated domain configuration to group_vars/all.yaml works well
- Health check tightening (10s/5 retries) is good baseline
- .bak rollback snapshots before deploy proved useful

### Pending Todos

None yet.

### Blockers/Concerns

None yet.
