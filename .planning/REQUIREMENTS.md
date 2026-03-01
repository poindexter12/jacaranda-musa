# Requirements: Musa Project

**Defined:** 2026-02-28
**Core Value:** A working, reproducible deployment pipeline that can reliably provision and update the Twenty CRM stack

## v1 Requirements

Requirements for this milestone. Each maps to roadmap phases.

### Pipeline

- [ ] **PIPE-01**: `just test::full` runs end-to-end without errors (Terraform apply + Ansible deploy)
- [ ] **PIPE-02**: `just test::deploy` re-deploys idempotently on existing LXC
- [ ] **PIPE-03**: `just test::validate` confirms all 9 containers healthy
- [ ] **PIPE-04**: `just check-secrets` passes for all 7 1Password items

### Upgrade

- [ ] **UPGR-01**: Twenty CRM server and worker containers run v1.18.0
- [ ] **UPGR-02**: Database migrations complete successfully during version upgrade
- [ ] **UPGR-03**: Application accessible at musa-project-test.joeseymour.io after upgrade

### Image Pinning

- [ ] **IMGP-01**: Backup container pinned to specific version tag (not `latest`)
- [ ] **IMGP-02**: Rollup container pinned to specific version tag (not `latest`)
- [ ] **IMGP-03**: Webhook receiver/worker containers pinned to specific version tags (not `latest`)

### Health Checks

- [ ] **HLTH-01**: Docker Compose health check timeouts tightened (10s interval, 5 retries max)
- [ ] **HLTH-02**: `just test::validate` includes external URL check via Cloudflare Tunnel
- [ ] **HLTH-03**: Ansible health check tasks include explicit curl timeouts

### Configuration

- [ ] **CONF-01**: Domain references use single variable (not hardcoded in multiple templates)
- [ ] **CONF-02**: Rollback recipe exists (`just test::rollback` or equivalent)
- [ ] **CONF-03**: Secrets exposure reduced (sensitive env vars marked or documented)

## v2 Requirements

Deferred to production milestone.

### Production

- **PROD-01**: Production environment deploys on separate node
- **PROD-02**: Resource limits configurable per environment (cores, memory)
- **PROD-03**: PostgreSQL resource constraints set (shared_buffers, memory limits)

### Monitoring

- **MNTR-01**: Backup failure alerts via webhook notification
- **MNTR-02**: Centralized log forwarding (syslog or Loki)
- **MNTR-03**: Redis memory usage monitoring

## Out of Scope

| Feature | Reason |
|---------|--------|
| Docker Swarm secrets | Requires Swarm mode; single-node Compose doesn't support it |
| Blue-green deployment | Overkill for single-node test environment |
| Multi-node HA | Production concern, not test |
| Proxmox provider upgrade to stable | Wait for stable 3.x release |
| Shared-libs submodule changes | Upstream repo; changes require separate PR |

## Traceability

Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| PIPE-01 | Phase 1 | Pending |
| PIPE-02 | Phase 1 | Pending |
| PIPE-03 | Phase 1 | Pending |
| PIPE-04 | Phase 1 | Pending |
| CONF-01 | Phase 2 | Pending |
| CONF-02 | Phase 2 | Pending |
| CONF-03 | Phase 2 | Pending |
| IMGP-01 | Phase 2 | Pending |
| IMGP-02 | Phase 2 | Pending |
| IMGP-03 | Phase 2 | Pending |
| UPGR-01 | Phase 3 | Pending |
| UPGR-02 | Phase 3 | Pending |
| UPGR-03 | Phase 3 | Pending |
| HLTH-01 | Phase 4 | Pending |
| HLTH-02 | Phase 4 | Pending |
| HLTH-03 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 16 total
- Mapped to phases: 16
- Unmapped: 0 ✓

---
*Requirements defined: 2026-02-28*
*Last updated: 2026-02-28 after roadmap creation*
