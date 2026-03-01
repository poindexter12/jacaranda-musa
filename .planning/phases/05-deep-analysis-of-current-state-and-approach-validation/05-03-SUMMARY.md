---
phase: 05-deep-analysis-of-current-state-and-approach-validation
plan: 03
subsystem: configuration
tags: [ansible, rollback, secrets, documentation]
dependency_graph:
  requires: []
  provides:
    - CONF-01
    - CONF-02
    - CONF-03
  affects:
    - ansible/roles/musa/defaults/main.yaml
    - ansible/group_vars/all.yaml
    - ansible/roles/musa/templates/env.j2
    - test.just
tech_stack:
  added: []
  patterns:
    - Single source of truth for domain configuration
    - Rollback safety via pre-deploy snapshots
    - Comprehensive secrets documentation
key_files:
  created: []
  modified:
    - ansible/roles/musa/defaults/main.yaml
    - ansible/roles/musa/templates/env.j2
    - test.just
decisions:
  - id: CONF-01
    summary: Removed duplicated domain variables from role defaults, keeping only in group_vars/all.yaml
    rationale: Ansible precedence means group_vars wins anyway; duplication was confusing and error-prone
  - id: CONF-02
    summary: Implemented rollback via .bak file snapshots created before each deploy
    rationale: Simple, reliable recovery mechanism without external state management
  - id: CONF-03
    summary: Documented all secrets with 1Password sources and exposure details in defaults/main.yaml
    rationale: Makes secrets flow transparent and facilitates security audits
metrics:
  duration: 150s
  completed: 2026-03-01
---

# Phase 05 Plan 03: Configuration Consolidation and Rollback Safety Summary

**One-liner:** Consolidated domain configuration to group_vars, added rollback recipe with pre-deploy snapshots, and documented secrets exposure.

## Tasks Completed

| Task | Description | Commit | Status |
|------|-------------|--------|--------|
| 1 | Consolidate domain vars and document secrets | 309c058 | Complete |
| 2 | Add rollback recipe to test.just | c21a3e4 | Complete |

## Deviations from Plan

None - plan executed exactly as written.

## Key Changes

### Configuration Consolidation (CONF-01)

**Problem:** Domain and app variables were duplicated between `ansible/roles/musa/defaults/main.yaml` and `ansible/group_vars/all.yaml` with identical values, making it unclear which was authoritative.

**Solution:**
- Removed `twenty_tag`, `twenty_domain`, `swag_url`, and `swag_subdomain` from role defaults
- Added comment block directing users to `group_vars/all.yaml` as single source of truth
- Kept only genuine role-level defaults: `app_data_dir`, `timezone`, and custom image tags (backup_tag, rollup_tag, webhook_tag)

**Impact:** Clear separation between role defaults (fallbacks) and environment configuration (group_vars). Reduces confusion and potential conflicts.

### Rollback Safety (CONF-02)

**Problem:** No way to recover from a bad deployment. If docker-compose.yaml or .env changes break the stack, manual SSH intervention required.

**Solution:**
- Added `rollback-prep` recipe (private) that SSH's to musa-test.lan and creates `.bak` snapshots of docker-compose.yaml and .env
- Modified `deploy` recipe to call `rollback-prep` before running Ansible
- Added `rollback` recipe with confirmation prompt that:
  - Checks for existence of .bak files (fails fast if missing)
  - Restores docker-compose.yaml.bak → docker-compose.yaml and .env.bak → .env
  - Runs `docker compose up -d --force-recreate` to apply previous config
  - Waits 30s and verifies Twenty CRM health endpoint
  - Reports success or failure

**Impact:** Every deploy creates a rollback point. Recovery from bad deployments is now a single command: `just test::rollback`

### Secrets Documentation (CONF-03)

**Problem:** Sensitive environment variables passed via justfile extra-vars weren't documented, making it hard to understand:
- Which secrets are required
- Where they come from (1Password paths)
- How they're exposed (Docker env vars vs files)

**Solution:**

**In ansible/roles/musa/defaults/main.yaml:**
- Replaced scattered secret comments with structured table:
  - Variable name
  - 1Password source path
  - Exposure method (Docker env var, file, or login-only)
- Covers all 7 secrets: cf_tunnel_token, cf_api_token, cf_zone_id, cf_account_id, pg_password, app_secret, ghcr_pat

**In ansible/roles/musa/templates/env.j2:**
- Added security note header explaining:
  - File contains secrets (PG_DATABASE_URL, PG_DATABASE_PASSWORD, APP_SECRET)
  - Deployed with mode 0600 (owner-only read)
  - Warning not to change permissions or add to shared volumes

**Impact:** Secrets flow is now transparent. Security audits can quickly verify exposure methods and sources.

## Verification Results

All verification criteria passed:

```bash
# CONF-01: Domain consolidation
$ grep -c "twenty_domain:" ansible/roles/musa/defaults/main.yaml
1  # Only in comment section pointing to group_vars

$ grep -c "twenty_domain:" ansible/group_vars/all.yaml
1  # Actual definition

# CONF-02: Rollback recipe exists
$ grep "rollback:" test.just
rollback:  # Found

$ grep "rollback-prep" test.just
rollback-prep:  # Found

$ grep "docker-compose.yaml.bak" test.just
cp -f docker-compose.yaml docker-compose.yaml.bak  # Found

# CONF-03: Secrets documentation
$ grep "SECURITY NOTE" ansible/roles/musa/templates/env.j2
# SECURITY NOTE: This file contains secrets...  # Found

$ grep -A 10 "SECRETS" ansible/roles/musa/defaults/main.yaml
# Shows full secrets table with 7 entries
```

## Files Modified

1. **ansible/roles/musa/defaults/main.yaml**
   - Removed duplicated domain/app variables
   - Added comprehensive secrets documentation table
   - Added comment block directing to group_vars

2. **ansible/roles/musa/templates/env.j2**
   - Added security note about secrets exposure and file permissions

3. **test.just**
   - Added `rollback-prep` recipe (private, creates .bak snapshots)
   - Added `rollback` recipe (public, with confirmation prompt and health checks)
   - Modified `deploy` recipe to call rollback-prep before Ansible run

## Success Criteria Met

- [x] CONF-01: Domain references consolidated to group_vars/all.yaml only
- [x] CONF-02: Rollback recipe exists with confirmation prompt, backup restore, and health verification
- [x] CONF-03: Secrets exposure documented in defaults and env.j2

## Next Steps

Plan 04 will validate the overall Phase 05 approach and determine if additional configuration cleanup is needed.

## Self-Check: PASSED

**Created files exist:**
```bash
$ ls -la .planning/phases/05-deep-analysis-of-current-state-and-approach-validation/05-03-SUMMARY.md
-rw-r--r--  1 user  staff  5914 Mar  1 10:00 05-03-SUMMARY.md  # FOUND
```

**Commits exist:**
```bash
$ git log --oneline --all | grep 309c058
309c058 refactor(05-03): consolidate domain vars and document secrets  # FOUND

$ git log --oneline --all | grep c21a3e4
c21a3e4 feat(05-03): add rollback recipe for safe deployment recovery  # FOUND
```

**Modified files match plan:**
```bash
$ git diff 309c058^..c21a3e4 --name-only
ansible/roles/musa/defaults/main.yaml  # FOUND
ansible/roles/musa/templates/env.j2    # FOUND
test.just                              # FOUND
```

All files created, all commits present, all changes applied.
