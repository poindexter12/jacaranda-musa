---
phase: 05-deep-analysis-of-current-state-and-approach-validation
plan: 02
subsystem: deployment-configuration
tags: [image-versioning, health-checks, reliability]
dependency_graph:
  requires:
    - plan: 05-01
      reason: Builds on project analysis findings
  provides:
    - Configurable GHCR image version tags
    - Tightened health check intervals and timeouts
    - Explicit curl/uri timeouts in Ansible verification
  affects:
    - ansible/roles/musa/templates/docker-compose.yaml.j2
    - ansible/roles/musa/defaults/main.yaml
    - ansible/roles/musa/tasks/main.yaml
    - ansible/group_vars/all.yaml
tech_stack:
  added: []
  patterns:
    - Jinja2 variable substitution for image tags
    - Explicit timeout flags in Docker health checks
    - Ansible uri module timeout parameter
key_files:
  created: []
  modified:
    - ansible/roles/musa/defaults/main.yaml: Added backup_tag, rollup_tag, webhook_tag variables
    - ansible/group_vars/all.yaml: Added custom image tag variables for environment overrides
    - ansible/roles/musa/templates/docker-compose.yaml.j2: Replaced :latest with variables, tightened health checks
    - ansible/roles/musa/tasks/main.yaml: Added explicit curl timeouts and reduced retry counts
decisions:
  - what: Use "latest" as default tag value
    why: Makes conscious choice explicit, user will pin to actual versions from GHCR
    alternatives: [Use specific version as default, Fail if not set]
  - what: Keep server start_period at 60s
    why: Database migrations on first start require significant time
    alternatives: [Reduce to 30s, Increase to 90s]
  - what: Reduce Ansible retry counts (30→12)
    why: With tighter intervals, 60-120s total wait is sufficient for healthy services
    alternatives: [Keep original 150-300s totals, Make configurable]
metrics:
  duration: 106
  tasks_completed: 2
  files_modified: 4
  commits: 2
  completed_at: "2026-03-01T17:47:42Z"
---

# Phase 05 Plan 02: Pin GHCR Images and Tighten Health Checks Summary

**One-liner:** Configured version tags for three custom GHCR images and tightened health check intervals from 30s to 10s with explicit timeouts.

## What Was Built

Implemented configurable version tags for custom container images and tightened health check configurations across both Docker Compose and Ansible verification tasks.

**Custom Image Version Tags:**
- Added `backup_tag`, `rollup_tag`, `webhook_tag` variables to role defaults and group_vars
- Replaced four hardcoded `:latest` tags with Jinja2 variable substitution
- Default to "latest" as explicit choice (user will pin to actual GHCR versions)

**Health Check Improvements:**
- Server and webhook-receiver health checks: 30s→10s interval, 3→5 retries
- Added `--max-time 5` and `-s` flags to curl commands in Docker health checks
- SWAG verification: Added `--max-time 5`, reduced retries 30→12 (60s total)
- Twenty healthz verification: Added `timeout: 10` to uri module, reduced retries 30→12 (120s total)

## Deviations from Plan

None - plan executed exactly as written.

## Requirements Satisfied

| Requirement ID | Description | Status |
| -------------- | ----------- | ------ |
| IMGP-01 | Backup image uses configurable version tag | ✅ Complete |
| IMGP-02 | Rollup image uses configurable version tag | ✅ Complete |
| IMGP-03 | Webhook-receiver image uses configurable version tag | ✅ Complete |
| HLTH-01 | Docker health checks use 10s interval with 5 retries | ✅ Complete |
| HLTH-03 | Ansible health checks include explicit timeouts | ✅ Complete |

## Implementation Details

### Task 1: Add image tag variables and pin GHCR images
**Commit:** 29e617d

Added three new variables to both role defaults and group_vars:
```yaml
backup_tag: "latest"
rollup_tag: "latest"
webhook_tag: "latest"
```

Updated docker-compose.yaml.j2 to use Jinja2 variable substitution for all custom GHCR images:
- `ghcr.io/.../backup:{{ backup_tag }}`
- `ghcr.io/.../rollup:{{ rollup_tag }}`
- `ghcr.io/.../webhook-receiver:{{ webhook_tag }}` (used by both receiver and worker containers)

**Files modified:** ansible/roles/musa/defaults/main.yaml, ansible/group_vars/all.yaml, ansible/roles/musa/templates/docker-compose.yaml.j2

**Verification:**
- ✅ 4 GHCR image references use variables
- ✅ Only 1 `:latest` remains (SWAG - LinuxServer.io image)
- ✅ Variables defined in both defaults and group_vars

### Task 2: Tighten health checks and add Ansible curl timeouts
**Commit:** b7aa340

**Docker Compose health checks:**
- Server: interval 30s→10s, timeout 10s→5s, retries 3→5
- Webhook-receiver: interval 30s→10s, retries 3→5
- Both: Added `--max-time 5` and `-s` flags to curl
- Server start_period: kept at 60s (DB migrations need time)

**Ansible verification tasks:**
- SWAG health check: Added `--max-time 5`, reduced retries 30→12, delay 5s (60s total)
- Twenty healthz check: Added `timeout: 10`, reduced retries 30→12, delay 10s (120s total)

**Files modified:** ansible/roles/musa/templates/docker-compose.yaml.j2, ansible/roles/musa/tasks/main.yaml

**Verification:**
- ✅ 2 `--max-time` flags in docker-compose.yaml.j2
- ✅ 2 timeout specifications in tasks/main.yaml (--max-time + timeout:)
- ✅ Health check intervals show 10s for server, db, webhook-receiver

## Testing Evidence

**Automated verification:**
```bash
# Task 1 verification
$ grep -c "backup_tag\|rollup_tag\|webhook_tag" docker-compose.yaml.j2
4  # ✅ All 4 GHCR images use variables

$ grep -c ':latest' docker-compose.yaml.j2
1  # ✅ Only SWAG image retains :latest

# Task 2 verification
$ grep -c "max-time" docker-compose.yaml.j2
2  # ✅ Server and webhook-receiver health checks

$ grep -c "max-time\|timeout:" tasks/main.yaml
2  # ✅ SWAG curl + Twenty uri timeouts

# Overall verification
$ grep 'interval: 10s' docker-compose.yaml.j2
      interval: 10s  # db
      interval: 10s  # server
      interval: 10s  # webhook-receiver
```

## Future Work

**User action required:**
1. Check GHCR for available version tags:
   - `ghcr.io/poindexter12/musa-project-twenty-crm/backup`
   - `ghcr.io/poindexter12/musa-project-twenty-crm/rollup`
   - `ghcr.io/poindexter12/musa-project-twenty-crm/webhook-receiver`
2. Pin versions in `ansible/group_vars/all.yaml` (test environment)
3. Run `just test::deploy` to verify new health check timings work correctly

**Next plan:** 05-03 (validation testing with actual deployment)

## Commits

| Hash | Message | Files |
| ---- | ------- | ----- |
| 29e617d | feat(05-02): pin GHCR images to version tags | 3 files (defaults, group_vars, docker-compose) |
| b7aa340 | feat(05-02): tighten health checks and add explicit timeouts | 2 files (docker-compose, tasks) |

## Self-Check

Verifying created files and commits exist:

```bash
# Check modified files
$ [ -f "ansible/roles/musa/defaults/main.yaml" ] && echo "✅ FOUND: defaults/main.yaml"
✅ FOUND: defaults/main.yaml

$ [ -f "ansible/group_vars/all.yaml" ] && echo "✅ FOUND: group_vars/all.yaml"
✅ FOUND: group_vars/all.yaml

$ [ -f "ansible/roles/musa/templates/docker-compose.yaml.j2" ] && echo "✅ FOUND: docker-compose.yaml.j2"
✅ FOUND: docker-compose.yaml.j2

$ [ -f "ansible/roles/musa/tasks/main.yaml" ] && echo "✅ FOUND: tasks/main.yaml"
✅ FOUND: tasks/main.yaml

# Check commits exist
$ git log --oneline --all | grep -q "29e617d" && echo "✅ FOUND: 29e617d"
✅ FOUND: 29e617d

$ git log --oneline --all | grep -q "b7aa340" && echo "✅ FOUND: b7aa340"
✅ FOUND: b7aa340
```

## Self-Check: PASSED

All modified files and commits verified.
