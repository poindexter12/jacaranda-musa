# Roadmap: Musa Project

## Overview

Post-split validation and hardening of the Twenty CRM deployment. Validate the extraction from the jacaranda monorepo didn't break the Terraform/Ansible pipeline, harden configuration (pin images, parameterize domains, add rollback), upgrade Twenty CRM from v1.17.0 to v1.18.0, then tighten health checks and external validation.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Pipeline Validation** - Prove repo split didn't break deployment
- [ ] **Phase 2: Configuration Hardening** - Pin images, parameterize domains, add rollback
- [ ] **Phase 3: Version Upgrade** - Twenty CRM v1.17.0 → v1.18.0
- [ ] **Phase 4: Health Check Hardening** - Tighten timeouts and add external validation

## Phase Details

### Phase 1: Pipeline Validation
**Goal**: Prove the repo split from jacaranda monorepo didn't break the deployment pipeline
**Depends on**: Nothing (first phase)
**Requirements**: PIPE-01, PIPE-02, PIPE-03, PIPE-04
**Success Criteria** (what must be TRUE):
  1. `just test::full` completes without errors (Terraform + Ansible)
  2. `just test::deploy` runs idempotently on existing LXC (no spurious changes)
  3. All 9 containers are healthy after deployment
  4. All 7 1Password items accessible via `just check-secrets`
**Plans**: 2 plans

Plans:
- [ ] 01-01-PLAN.md — Fix validate recipe (all 9 containers) and check-secrets path alignment
- [ ] 01-02-PLAN.md — Run full pipeline and validate (human checkpoint)

### Phase 2: Configuration Hardening
**Goal**: Reduce operational risk before version upgrade (pin images, parameterize domains, add rollback)
**Depends on**: Phase 1
**Requirements**: CONF-01, CONF-02, CONF-03, IMGP-01, IMGP-02, IMGP-03
**Success Criteria** (what must be TRUE):
  1. Backup, rollup, and webhook containers use pinned version tags (not `latest`)
  2. Domain references consolidated to single variable source
  3. Rollback procedure exists and documented
  4. Sensitive environment variables documented (secrets exposure mapped)
**Plans**: TBD

Plans:
- [ ] TBD

### Phase 3: Version Upgrade
**Goal**: Upgrade Twenty CRM from v1.17.0 to v1.18.0
**Depends on**: Phase 2
**Requirements**: UPGR-01, UPGR-02, UPGR-03
**Success Criteria** (what must be TRUE):
  1. Server and worker containers running v1.18.0
  2. Database migrations completed successfully (no errors in logs)
  3. Application accessible at musa-project-test.joeseymour.io (external access works)
  4. Existing data intact (no data loss)
**Plans**: TBD

Plans:
- [ ] TBD

### Phase 4: Health Check Hardening
**Goal**: Tighten health check timeouts and add external validation
**Depends on**: Phase 3
**Requirements**: HLTH-01, HLTH-02, HLTH-03
**Success Criteria** (what must be TRUE):
  1. Docker Compose health checks use 10s interval with 5 retry max
  2. `just test::validate` includes external URL check via Cloudflare Tunnel
  3. Ansible health check tasks have explicit curl timeouts
  4. Failed health checks surface quickly (not hanging indefinitely)
**Plans**: TBD

Plans:
- [ ] TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Pipeline Validation | 0/2 | Not started | - |
| 2. Configuration Hardening | 0/TBD | Not started | - |
| 3. Version Upgrade | 0/TBD | Not started | - |
| 4. Health Check Hardening | 0/TBD | Not started | - |
