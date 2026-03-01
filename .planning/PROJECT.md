# Musa Project — Twenty CRM Service

## What This Is

Infrastructure-as-Code repository for deploying Twenty CRM on a Proxmox LXC container with SWAG reverse proxy and Cloudflare Tunnel. Split from the main jacaranda monorepo into a standalone service repo. Currently deployed at musa-project-test.joeseymour.io running v1.17.0.

## Core Value

A working, reproducible deployment pipeline (Terraform → Ansible → Docker Compose) that can reliably provision and update the Twenty CRM stack from a single `just test::full` command.

## Requirements

### Validated

<!-- Inferred from existing codebase — these capabilities already exist and work. -->

- ✓ LXC container provisioning via Terraform/OpenTofu on Proxmox — existing
- ✓ Docker-in-LXC with nesting enabled — existing
- ✓ 9-container Docker Compose stack (SWAG, Twenty server/worker, PostgreSQL, Redis, backup, rollup, webhook receiver/worker) — existing
- ✓ SWAG reverse proxy with Let's Encrypt SSL via Cloudflare DNS-01 challenge — existing
- ✓ Cloudflare Tunnel for external access without port forwarding — existing
- ✓ 1Password secret injection at deploy time via justfile recipes — existing
- ✓ Ansible role with idempotent tasks, health checks, and handler-based restarts — existing
- ✓ Shared library submodule (jacaranda-shared-libs v1.4.0) for Terraform modules and justfile utilities — existing
- ✓ PostgreSQL automated backups with 7-day retention — existing
- ✓ Webhook receiver/worker for external integrations — existing
- ✓ Analytics rollup cron job (2 AM daily) — existing

### Active

<!-- Current scope — what this milestone delivers. -->

- [ ] Pipeline verification after repo split (Terraform + Ansible run cleanly end-to-end)
- [ ] Upgrade Twenty CRM from v1.17.0 to v1.18.0
- [ ] Pin custom GHCR images to specific versions instead of `latest` tag
- [ ] Improve secrets management (reduce plaintext exposure in container env vars)
- [ ] Add rollback procedure for configuration changes
- [ ] Tighten health check timeouts and retry logic
- [ ] Add external Cloudflare Tunnel connectivity validation to `just test::validate`
- [ ] Parameterize hardcoded domain references into single source of truth

### Out of Scope

- Production environment deployment — deferred to next milestone
- Centralized log aggregation (ELK/Loki) — infrastructure complexity not justified for test
- Docker secrets management migration — requires Docker Swarm or external secrets manager
- Blue-green deployment — overkill for single-node test environment
- Multi-node HA setup — production concern, not test

## Context

This repo was extracted from a larger jacaranda monorepo. The test deployment at musa-project-test.joeseymour.io is live and running v1.17.0 but the pipeline hasn't been validated since the split. The shared-libs submodule (v1.4.0) provides Terraform modules and justfile utilities that were previously available in-tree.

The codebase map at `.planning/codebase/` documents the current state including a thorough concerns audit (CONCERNS.md) that identified issues with `latest` image tags, loose health checks, hardcoded domains, and secrets exposed as environment variables.

Twenty CRM upstream released v1.18.0 on 2026-02-19.

## Constraints

- **Infrastructure**: Single LXC on Proxmox node "joseph" (VMID 1180, 4 cores, 4GB RAM, 20G Ceph)
- **Secrets**: 1Password CLI required; 7 items in `op://Homelab/` vault
- **Network**: External access via Cloudflare Tunnel only (no port forwarding)
- **Dependencies**: Shared-libs submodule pinned to v1.4.0; changes require upstream PR
- **Provider**: Proxmox provider at RC version (3.0.2-rc07); upgrade when stable available

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Target v1.18.0 specifically | User confirmed this release (2026-02-19) | — Pending |
| Address CONCERNS.md items in this milestone | Improve operational reliability before prod | — Pending |
| Keep test environment only | Prod deployment is next milestone | — Pending |
| Stay on shared-libs v1.4.0 | No upstream changes needed for this work | — Pending |

---
*Last updated: 2026-02-28 after initialization*
