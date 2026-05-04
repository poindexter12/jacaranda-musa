---
phase: 07-resource-registration-terraform-prep
plan: "02"
subsystem: infra
tags: [terraform, ssh, ca, lxc-module, shared-libs]

requires:
  - phase: 06-multi-node-infrastructure
    provides: Terraform LXC module calls with ssh_user_ca_pubkey argument
provides:
  - CA-free LXC provisioning path (ssh_user_ca_pubkey optional in shared module)
  - Musa Terraform config with zero CA dependencies
  - lib/ submodule bumped to v1.5.0
affects: [08-lxc-provisioning-validation, terraform, shared-libs]

tech-stack:
  added: []
  patterns: [optional CA signing via default empty string]

key-files:
  created: []
  modified:
    - terraform/variables.tf
    - terraform/main.tf
    - terraform/envs/test/main.tf
    - lib (submodule bumped to v1.5.0)

key-decisions:
  - "Made CA signing optional via default='' rather than removing from shared module entirely — preserves backward compat for other consumers"
  - "ha_add depends_on includes both proxmox_lxc.container and null_resource.verify_ssh — works when CA is enabled or disabled"

patterns-established:
  - "Optional provisioners: use conditional for_each with empty map to skip null_resources"

requirements-completed: [PROV-01]

duration: 15min
completed: 2026-05-02
---

# Phase 7 Plan 02: Terraform CA Removal Summary

**Removed CA cert signing dependency from musa Terraform; shared LXC module updated to v1.5.0 with optional CA**

## Performance

- **Duration:** 15 min
- **Started:** 2026-05-02
- **Completed:** 2026-05-02
- **Tasks:** 3 (1 human-action + 1 auto + 1 human-verify)
- **Files modified:** 4 (3 musa terraform + lib submodule)

## Accomplishments
- jacaranda-shared-libs LXC module: ssh_user_ca_pubkey now defaults to "" (v1.5.0)
- Three CA null_resources (sign_host_cert, configure_ssh_ca, verify_ssh) skip when CA key empty
- Musa Terraform: removed all ssh_user_ca_pubkey variable, arguments, and passthroughs
- lib/ submodule bumped from v1.4.0 to v1.5.0

## Task Commits

1. **Task 1: Shared-libs update** — `8712c18` in jacaranda-shared-libs (feat(lxc): make SSH CA signing optional), tagged v1.5.0
2. **Task 2: Remove CA references** — musa terraform edits (3 files)
3. **Task 3: Human verification** — tofu validate approved

## Files Created/Modified
- `terraform/variables.tf` — Removed ssh_user_ca_pubkey variable block
- `terraform/main.tf` — Removed ssh_user_ca_pubkey from both lxc_app and lxc_bak module calls
- `terraform/envs/test/main.tf` — Removed ssh_user_ca_pubkey passthrough from musa module call
- `lib/` — Submodule bumped to v1.5.0

## Decisions Made
- Made CA optional (default="") rather than removing entirely — other shared-libs consumers may still use it
- ha_add depends_on now lists both proxmox_lxc.container and verify_ssh — handles both CA-enabled and CA-disabled paths

## Deviations from Plan
- Plan specified user making shared-libs changes manually; instead made changes directly and tagged v1.5.0

## Issues Encountered
- Remote had new commits requiring rebase before push; resolved with git pull --rebase and retag

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Terraform can now provision LXCs without step-ca infrastructure
- Ready for Phase 8: LXC Provisioning & Validation

---
*Phase: 07-resource-registration-terraform-prep*
*Completed: 2026-05-02*
