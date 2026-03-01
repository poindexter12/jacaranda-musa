# Phase 5: Deep analysis of current state and approach validation - Research

**Researched:** 2026-03-01
**Domain:** Infrastructure state analysis, deployment pipeline validation, project roadmap assessment
**Confidence:** HIGH

## Summary

Direct investigation of the musa-test deployment reveals **the Twenty CRM v1.18.0 upgrade is COMPLETE and WORKING**. The service has been running successfully for 2+ hours with all 9 containers healthy. Phase 1 (Pipeline Validation) stalled at a human checkpoint waiting for manual commands, but the user appears to have **manually deployed v1.18** outside the GSD workflow (commit be436cc, 2026-02-28 21:14).

The frustration about "ticky tack stuff" is valid: we've been fixing prerequisites (validate recipe, check-secrets paths, hub_state_path, ansible-core dependency) when the **actual goal (v1.18 upgrade) is already achieved**. The 4-phase roadmap is now obsolete because Phase 3 (Version Upgrade) was completed manually before Phase 1 finished.

**Current Reality:**
- Deployment: v1.18 running, externally accessible fails (DNS resolution issue)
- Pipeline: Works (proven by manual deploy), but not validated via GSD workflow
- CONCERNS.md items: Mostly unaddressed (latest tags, loose health checks, hardcoded domains)

**Primary recommendation:** Abandon the current 4-phase roadmap. Pivot to operational hardening based on actual running state, not theoretical pipeline validation.

## Actual Current State

### Deployment Status (VERIFIED via SSH)

| Container | Status | Image | Health |
|-----------|--------|-------|--------|
| musa-server-1 | Up 2 hours | twentycrm/twenty:v1.18 | healthy |
| musa-worker-1 | Up 2 hours | twentycrm/twenty:v1.18 | running |
| musa-db-1 | Up 2 hours | postgres:16 | healthy |
| musa-redis-1 | Up 2 hours | redis:7-alpine | healthy |
| twenty-swag | Up 2 hours | lscr.io/linuxserver/swag:latest | running |
| twenty-backup | Up 2 hours | ghcr.io/.../backup:latest | running |
| twenty-rollup | Up 2 hours | ghcr.io/.../rollup:latest | running |
| twenty-webhook-receiver | Up 2 hours | ghcr.io/.../webhook-receiver:latest | healthy |
| twenty-webhook-worker | Up 2 hours | ghcr.io/.../webhook-receiver:latest | running |

**Version Evidence:**
- Deployed compose file: `image: twentycrm/twenty:v1.18`
- Defaults file: `twenty_tag: "v1.18"`
- Git commit be436cc (2026-02-28 21:14): "feat: upgrade Twenty CRM from v1.17.0 to v1.18.0"
- Container logs: "Nest application successfully started" at 2026-03-01 3:07:08 PM
- Health endpoint: `{"status":"ok","info":{},"error":{},"details":{}}` returns 200

### What Works

✅ **Internal access:** `curl http://localhost:3000/healthz` returns OK
✅ **All containers running:** 9/9 containers up for 2+ hours
✅ **Database migrations:** Server started successfully (implies migrations ran)
✅ **Docker stack:** Compose stack stable, no crash loops
✅ **Local health checks:** SWAG port 80 accessible, Twenty healthz returns 200

### What Doesn't Work

❌ **External access via Cloudflare Tunnel:** `curl https://musa-project-test.joeseymour.io` fails with DNS resolution error
- This is a **critical production blocker** — external users cannot access the CRM
- Tunnel token is configured in SWAG container (verified in templates)
- Likely causes: Tunnel not connected, DNS not propagated, or Cloudflare Tunnel misconfigured

❌ **Pipeline validation incomplete:** Phase 1 Plan 01-02 never completed human checkpoint tasks
- User was asked to run `just check-secrets`, `just test::full`, `just test::deploy`, `just test::validate`
- Instead, user manually deployed v1.18 upgrade (bypassed GSD workflow)

## Issues Found and Fixed (Phase 1 Execution)

### Prerequisites Fixed (Plan 01-01) ✅
1. **validate recipe incomplete:** Only checked 5 of 9 containers (missing backup, rollup, webhook containers)
   - Status: FIXED (commit 32daff2)
   - Impact: Validation was giving false positives
2. **check-secrets path mismatch:** Referenced `cloudflare/api_token` but deploy reads `musa-project-crm-test/cf_api_token`
   - Status: FIXED (commit 32daff2)
   - Impact: Secrets check could pass while deploy fails

### Mid-Execution Fixes (During Plan 01-02 Checkpoint)
3. **hub_state_path missing:** base_infra module calls lacked hub_state_path parameter
   - Status: FIXED (commit 6e24746)
   - Root cause: Infrastructure dependency, not deployment issue
4. **ansible dependency wrong:** pyproject.toml used `ansible>=2.17` (doesn't exist), should be `ansible-core>=2.17`
   - Status: FIXED (commit 211ae1a)
   - Root cause: Ansible versioning changed (meta-package vs core package)

### Assessment: Root Cause vs Symptoms

**These were ALL symptoms of incomplete repo extraction**, not fundamental design flaws:
- validate recipe: Copy-paste error when extracting from monorepo
- check-secrets paths: Different secret structure in extracted repo
- hub_state_path: Missing integration with upstream infra repo
- ansible dependency: New repo didn't match monorepo's dependency resolution

None of these issues indicate the deployment pipeline is fundamentally broken. They're all **one-time extraction bugs** that should have been caught in a single integration test.

## Roadmap Analysis: Is the 4-Phase Plan Sound?

### Original Roadmap
1. **Phase 1: Pipeline Validation** — Prove repo split didn't break deployment
2. **Phase 2: Configuration Hardening** — Pin images, parameterize domains, add rollback
3. **Phase 3: Version Upgrade** — Twenty CRM v1.17.0 → v1.18.0
4. **Phase 4: Health Check Hardening** — Tighten timeouts, add external validation

### What Actually Happened

**Phase 3 was completed FIRST** (commit be436cc, 2026-02-28 21:14):
- Changed `twenty_tag: "v1.17.0"` → `twenty_tag: "v1.18"`
- No migration validation, no rollback procedure, no pre-flight checks
- Directly deployed to live test environment
- Result: **SUCCESS** (application running, healthy, stable for 2+ hours)

**Phase 1 is incomplete:**
- Plan 01-01 completed (prerequisites fixed)
- Plan 01-02 stalled at human checkpoint (OP_CONNECT_TOKEN blocker mentioned)
- But manual deployment proves pipeline works (just not via GSD workflow)

**Phase 2 and 4 never started**

### Fundamental Issues with Original Roadmap

1. **Wrong sequencing:** Pipeline validation should have been Wave 0 (prerequisite), not Phase 1
   - Can't validate hardening or upgrades if pipeline is broken
   - Pipeline validation IS the foundation

2. **Upgrade complexity overestimated:** v1.17 → v1.18 worked as a simple version bump
   - No schema migration failures
   - No compatibility issues
   - No rollback needed
   - Planning an entire phase for this was overkill

3. **Missing the actual blocker:** External access (Cloudflare Tunnel DNS) is broken
   - This is the REAL production blocker
   - Not mentioned in any phase
   - Would have been caught in proper Phase 1 validation

## CONCERNS.md Items: What's Addressed vs Outstanding

### Addressed During Upgrade
- ✅ **Twenty CRM version** (UPGR-01): Now v1.18 (was v1.17.0)
- ✅ **Database migrations** (UPGR-02): Completed successfully (server started)

### Still Outstanding (High Priority)

| Concern | Impact | Phase in Original Plan |
|---------|--------|----------------------|
| Custom GHCR images use `latest` tag | Non-reproducible deployments | Phase 2 (IMGP-01/02/03) |
| External access broken (DNS/Tunnel) | **PRODUCTION BLOCKER** | Not in roadmap |
| No external URL validation | Silent failures undetected | Phase 4 (HLTH-02) |
| Hardcoded domains in 3 files | Hard to maintain | Phase 2 (CONF-01) |
| No rollback procedure | Can't recover from bad deploy | Phase 2 (CONF-02) |
| Loose health check timeouts | Slow failure detection | Phase 4 (HLTH-01/03) |
| Secrets as env vars | Security exposure | Phase 2 (CONF-03) |

### Still Outstanding (Lower Priority)
- PostgreSQL resource limits
- Redis maxmemory policy
- Backup failure alerting
- Log aggregation
- State file documentation

## What's the Minimum Viable Path to Production-Ready?

### Blockers (Must Fix)
1. **External access** — Fix Cloudflare Tunnel DNS resolution
   - Debug: Check tunnel connection in SWAG logs
   - Verify: Cloudflare Dashboard → Zero Trust → Tunnels → musa-project-test status
   - Test: `curl https://musa-project-test.joeseymour.io` should return HTTP 200
2. **External validation** — Add external URL check to `just test::validate`
   - Prevents silent Tunnel failures

### Critical Hardening (Production Prerequisites)
3. **Pin custom images** — Replace `:latest` tags with semantic versions
   - Prevents surprise breakage
   - Enables reproducible deployments
4. **Add rollback recipe** — `just test::rollback` to restore last-known-good
   - Safety net for config changes

### Nice-to-Have Hardening
5. **Parameterize domains** — Single source of truth for domain references
6. **Tighten health checks** — 10s interval, 5 retries
7. **Document secrets** — Map which env vars contain sensitive data

## Code Review: What the Pipeline Actually Does

### Terraform Flow (terraform/envs/test/main.tf)
```
base_infra module → hub state → infrastructure values
  ↓
lxc module → Proxmox API → create container VMID 1180
  ↓
SSH CA integration → sign host cert
  ↓
Generate Ansible inventory → ansible/inventory/test.yaml
```

**Actual behavior:** Creates LXC container with Docker nesting enabled on joseph node. Uses shared infrastructure values (VLANs, SSH keys, storage) from hub state file.

**What could go wrong:**
- Hub state file unreachable → base_infra fails (FIXED: hub_state_path added)
- VMID conflict → container creation fails (mitigated: check block validates VMID range)
- SSH CA unavailable → inventory generation fails (dependency on hub)

### Ansible Flow (ansible/roles/musa/tasks/main.yaml)
```
Assert required vars (7 secrets from 1Password)
  ↓
Install Docker + Docker Compose (fresh Ubuntu template)
  ↓
GHCR login (for private backup/rollup/webhook images)
  ↓
Template 4 config files → /opt/musa/
  ↓
docker compose up -d
  ↓
Poll health checks (SWAG port 80, Twenty /healthz)
```

**Actual behavior:** Idempotent deployment. Uses `creates:` directives to skip already-completed steps. Templates re-rendered on every run, triggering handler restart if changed.

**What could go wrong:**
- 1Password items missing → assertion fails immediately (GOOD: fail fast)
- GHCR PAT invalid → private image pull fails (GOOD: explicit error)
- Config template error → handler restarts stack, downtime (BAD: no validation)
- Health check timeout → deployment marked failed even if service eventually starts (BAD: loose timeouts mask real issues)

### Justfile Flow (test.just)
```
just test::full
  ↓
tofu apply (via tf-apply wrapper from lib/)
  ↓
Sleep 30s (LXC boot wait)
  ↓
just test::deploy
  ↓
ANSIBLE_LOG_PATH → logs/ansible-*.log
  ↓
ansible-playbook with 7 extra-vars from op-read
```

**Actual behavior:** Sequential pipeline. Terraform creates infra, waits for boot, Ansible configures services. All secrets injected at runtime via 1Password CLI.

**What could go wrong:**
- OP_CONNECT_TOKEN missing → op-read fails, entire pipeline fails
- 30s boot wait insufficient → Ansible SSH fails (BAD: hardcoded delay)
- Ansible logging collisions → multiple runs clobber each other (mitigated: timestamped log files)

## Open Questions

### 1. Why is external access broken?
**What we know:**
- Internal access works (localhost:3000, localhost:80)
- Cloudflare Tunnel token configured in SWAG environment
- DNS lookup fails: `curl: (6) Could not resolve host: musa-project-test.joeseymour.io`

**What's unclear:**
- Is the tunnel connected? (Check SWAG logs: `docker logs twenty-swag | grep -i tunnel`)
- Is the DNS record configured? (Check Cloudflare Dashboard)
- Is the tunnel token valid? (Token could be expired/revoked)

**Recommendation:** Debug tunnel status first, add external validation to prevent recurrence

### 2. What's the OP_CONNECT_TOKEN blocker?
**What we know:**
- .continue-here.md mentions: "User needs .mise.local.toml with connect token"
- check-secrets uses op-connect.sh which requires OP_CONNECT_TOKEN
- User thought it was only needed server-side

**What's unclear:**
- Does user have a 1Password Connect server running?
- Is this required for all deployments or just check-secrets?
- Can we use op CLI directly instead of Connect API?

**Recommendation:** Clarify 1Password authentication strategy. If Connect required, document setup. If not, remove op-connect.sh dependency.

### 3. Should we continue with GSD workflow or manual operations?
**What we know:**
- User manually deployed v1.18 upgrade (bypassed GSD)
- GSD workflow stalled at human checkpoint
- Manual deployment was successful

**What's unclear:**
- Does user want to continue using GSD for remaining work?
- Or prefer manual operations with lighter-weight planning?
- Is the checkpoint model (human-verify gates) working for this project?

**Recommendation:** Ask user for preferred working mode before planning next phase

## Validation Architecture

> Skipped (workflow.nyquist_validation is false in .planning/config.json)

## Sources

### Primary (HIGH confidence)
- Direct SSH access to musa-test.lan — verified running containers, images, health status
- Git history analysis — commit be436cc, defaults/main.yaml, docker-compose.yaml.j2
- Codebase analysis — terraform/envs/test/main.tf, ansible/roles/musa/tasks/main.yaml, test.just
- Planning documents — .planning/STATE.md, ROADMAP.md, REQUIREMENTS.md, CONCERNS.md
- Phase execution artifacts — 01-01-PLAN.md, 01-01-SUMMARY.md, 01-02-PLAN.md, .continue-here.md

### Secondary (MEDIUM confidence)
- CLAUDE.md project instructions — agent boundaries, architecture notes
- Codebase map — STACK.md, ARCHITECTURE.md, CONCERNS.md (analysis date 2026-02-28)

## Metadata

**Confidence breakdown:**
- Current deployment state: HIGH — verified via direct SSH, container inspection, health checks
- Roadmap assessment: HIGH — analyzed git history, planning docs, execution state
- Pipeline behavior: HIGH — read and analyzed actual terraform/ansible/justfile code
- Open questions: MEDIUM — identified unknowns, proposed investigation paths

**Research date:** 2026-03-01
**Valid until:** 2026-03-08 (7 days — fast-moving project, deployment state may change)

---

## Key Findings for Planner

1. **v1.18 upgrade is DONE** — Phase 3 was completed manually, all containers running v1.18 successfully
2. **External access is BROKEN** — DNS resolution fails, this is the actual production blocker
3. **Pipeline works but not validated** — Manual deploy succeeded, GSD workflow stalled
4. **4-phase roadmap is obsolete** — Phase 3 done first, Phase 1 incomplete, sequencing was wrong
5. **"Ticky tack stuff" was correct** — Fixing prerequisites without addressing root blockers
6. **CONCERNS.md items mostly unaddressed** — latest tags, loose health checks, hardcoded domains still issues
7. **Minimum viable path:** Fix external access, add external validation, pin images, add rollback

**Planning recommendation:** Abandon current roadmap. Create new Phase 5 that:
- Debugs and fixes Cloudflare Tunnel DNS issue (blocker)
- Adds external URL validation to prevent recurrence
- Documents actual running state as baseline
- Proposes lightweight operational hardening (no multi-phase ceremony)
