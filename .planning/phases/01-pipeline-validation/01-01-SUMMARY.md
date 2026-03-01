---
phase: 01-pipeline-validation
plan: 01
subsystem: ci-validation
tags: [validation, secrets, deployment]
dependency_graph:
  requires: []
  provides: [accurate-container-validation, aligned-secret-paths]
  affects: [test-deployment-workflow]
tech_stack:
  added: []
  patterns: []
key_files:
  created: []
  modified:
    - test.just
    - justfile
decisions:
  - decision: "Fixed validate recipe to check all 9 containers instead of 5"
    rationale: "Validation must verify the complete deployed stack"
    alternatives: []
    impact: "Validation now catches missing backup, rollup, and webhook containers"
  - decision: "Aligned check-secrets to verify musa-project-crm-test/cf_api_token"
    rationale: "Secrets check must validate the same paths that deploy recipe reads"
    alternatives: []
    impact: "Prevents false-positive secret validation when deploy would fail"
metrics:
  duration_seconds: 45
  tasks_completed: 1
  tasks_total: 1
  files_modified: 2
  commits: 1
  completed_at: "2026-03-01T02:46:02Z"
---

# Phase 01 Plan 01: Pipeline Validation Prerequisites Summary

**One-liner:** Fixed validate and check-secrets recipes to accurately reflect the complete 9-container stack and aligned 1Password paths

## Objective

Fix the validate recipe and check-secrets recipe so they accurately reflect the deployed stack before running pipeline validation.

## Context

The validate recipe only checked 5 of 9 containers (missing twenty-backup, twenty-rollup, twenty-webhook-receiver, twenty-webhook-worker). The check-secrets recipe referenced `cloudflare/api_token` but the deploy recipe reads `musa-project-crm-test/cf_api_token` -- a path mismatch that meant secrets check could pass while deploy fails.

## Execution Summary

### Tasks Completed

| Task | Status | Commit | Files Modified |
|------|--------|--------|----------------|
| 1. Add missing containers to validate recipe and fix check-secrets paths | ✓ | 32daff2 | test.just, justfile |

### Changes Made

**test.just (validate recipe):**
- Updated container loop from 5 containers to all 9 containers
- Added: twenty-backup, twenty-rollup, twenty-webhook-receiver, twenty-webhook-worker
- Validation now checks complete deployed stack

**justfile (check-secrets recipe):**
- Changed `Homelab/cloudflare/api_token` to `Homelab/musa-project-crm-test/cf_api_token`
- check-secrets now verifies the exact path that deploy recipe reads
- Eliminates false-positive validation

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

All automated verification passed:
- ✓ twenty-backup present in test.just
- ✓ twenty-rollup present in test.just
- ✓ twenty-webhook-receiver present in test.just
- ✓ twenty-webhook-worker present in test.just
- ✓ musa-project-crm-test/cf_api_token present in justfile
- ✓ cloudflare/api_token removed from justfile (no matches)

## Success Criteria Met

- ✓ validate recipe checks all 9 containers
- ✓ check-secrets paths match deploy recipe paths

## Impact

**Immediate:**
- Validation now catches missing backup containers
- Validation now catches missing rollup containers
- Validation now catches missing webhook containers
- Secrets verification aligned with actual deployment requirements

**Downstream:**
- Pipeline validation (plan 01-02) will now execute against accurate baseline
- Future deployments benefit from complete health checks
- Reduced false-positive/false-negative validation results

## Next Steps

Continue to plan 01-02 (pipeline validation execution) with accurate validation recipes in place.

## Self-Check: PASSED

**Created files verified:** N/A (no new files created)

**Modified files verified:**
```
FOUND: test.just
FOUND: justfile
```

**Commits verified:**
```
FOUND: 32daff2
```
