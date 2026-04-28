# Milestones: Musa Project

## v1.17 — Post-Split Validation & Hardening

**Status:** Partial (superseded by v2.0)
**Dates:** 2026-02-28 → 2026-03-01
**Phases:** 1–5 (Phase 5 superseded Phases 1–4)

**What shipped:**
- Pipeline validation after monorepo split
- Validate recipe checking all 9 containers
- check-secrets alignment for all 7 1Password items
- GHCR image pinning (configurable version tags for backup, rollup, webhook containers)
- Health check tightening (10s interval, 5 retries, explicit curl timeouts)
- Domain consolidation to group_vars/all.yaml single source of truth
- Rollback procedure via .bak snapshots before each deploy
- Secrets documentation with 1Password sources and exposure details
- External URL validation in test::validate recipe

**Not shipped (carried forward or dropped):**
- PIPE-01: Full end-to-end pipeline validation (not run)
- PIPE-02: Idempotent redeploy validation (not run)
- UPGR-01/02/03: Twenty CRM v1.18.0 upgrade (deferred)
- HLTH-02: External URL check via Cloudflare Tunnel (local env lacks tunnel)
- 05-04-PLAN: Final end-to-end validation plan (not executed)

**Key decisions:**
- Docker-in-LXC pattern validated as workable
- SWAG + Cloudflare Tunnel approach works for external access
- 1Password secret injection via op-read script is reliable
- Phase 5 consolidated approach better than incremental phases

**Last phase:** 5
