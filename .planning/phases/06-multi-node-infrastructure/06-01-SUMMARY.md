---
phase: 06-multi-node-infrastructure
plan: "01"
subsystem: infra
tags: [terraform, opentofu, proxmox, lxc, ansible, dual-nic, ha-cluster]

# Dependency graph
requires: []
provides:
  - 3-node LXC Terraform config (VMIDs 1190-1192) across joseph/everette/maxwell
  - Dual-NIC instances (mgmt .5.x / transfer .11.x) via LXC module transfer_ip support
  - Extended instances variable type with node_role and per-instance resource overrides
  - Custom multi-group Ansible inventory generation via local_file + yamlencode
  - Five inventory groups: musa, etcd_nodes, patroni_nodes, app_nodes, backup_nodes
  - Per-host inventory vars: ansible_host, mgmt_ip, transfer_ip, node_role, vmid
affects:
  - 06-02 (next plan in phase 06)
  - All subsequent HA phases that depend on the 3-node LXC cluster and multi-group inventory

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Dual LXC module calls for per-tier resource sizing (lxc_app + lxc_bak)
    - local_file + yamlencode for custom multi-group Ansible inventory generation
    - Strip musa-specific fields (node_role, cores, memory, disk_size) before passing to LXC module
    - coalesce(per-instance-override, module-default) for backup node resource resolution

key-files:
  created: []
  modified:
    - terraform/variables.tf
    - terraform/envs/test/main.tf
    - terraform/main.tf
    - terraform/outputs.tf

key-decisions:
  - "Two LXC module calls (lxc_app + lxc_bak) to handle per-tier resource sizing since shared LXC module applies resources uniformly"
  - "Strip musa-specific fields before passing instances to LXC module — LXC module only accepts vmid/node/mgmt_ip/transfer_ip/tags"
  - "ansible_inventory_path=null on both LXC module calls — custom local_file inventory replaces built-in single-group generator"
  - "etcd_nodes and patroni_nodes both contain all 3 hosts from day one per D-10 (all nodes run etcd and Patroni)"

patterns-established:
  - "Tier split: for-expression filters instances by node_role to create app_instances and bak_instances maps"
  - "Resource extraction: one([for...]) to get single backup node, then coalesce(override, default)"
  - "Inventory generation: yamlencode(local.ansible_inventory) with nested children groups"

requirements-completed: [INFRA-01, INFRA-02, INFRA-03]

# Metrics
duration: 7min
completed: 2026-04-28
---

# Phase 06 Plan 01: Multi-Node Infrastructure Summary

**3-node LXC cluster across joseph/everette/maxwell with dual-NIC networking and custom multi-group Ansible inventory generation via Terraform local_file + yamlencode**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-28T20:23:48Z
- **Completed:** 2026-04-28T20:30:59Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Extended `instances` variable type with `transfer_ip`, `node_role`, and optional `cores`/`memory`/`disk_size` overrides
- Replaced single `module "lxc"` with dual tier calls (`lxc_app` 4c/4096M/20G, `lxc_bak` 2c/2048M/40G) to handle heterogeneous resource sizing
- Custom multi-group Ansible inventory (5 groups: musa, etcd_nodes, patroni_nodes, app_nodes, backup_nodes) with per-host variables generated via `local_file` + `yamlencode`
- `tofu validate` passes

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend variables and 3-node env config** - `1d12189` (feat)
2. **Task 2: Dual LXC module calls and multi-group inventory** - `9a7f2bf` (feat)

## Files Created/Modified

- `terraform/variables.tf` - Extended instances type with transfer_ip, node_role, optional resource overrides; added ansible_inventory_path variable
- `terraform/envs/test/main.tf` - Replaced single musa-test (VMID 1180) with 3-node cluster: app1/app2/bak (VMIDs 1190-1192, per D-15 to D-18)
- `terraform/main.tf` - Dual LXC module calls (lxc_app + lxc_bak), tier-split locals, backup resource coalesce, custom 5-group inventory via local_file
- `terraform/outputs.tf` - Merges from both module calls, adds transfer_ips output, updates ansible_inventory_path to reference local_file resource

## Decisions Made

- **Two LXC module calls over one:** The shared LXC module applies resources uniformly — two calls with separate resource params is the clean solution for heterogeneous sizing (Option A from PATTERNS.md).
- **Field stripping before LXC module:** The LXC module `instances` type only accepts `vmid`, `node`, `mgmt_ip`, `speed_ip`, `transfer_ip`, `trusted_ip`, `tags`. Musa-specific fields (`node_role`, `cores`, `memory`, `disk_size`) must be projected out before passing to the module. This was discovered reading `lib/.../lxc/variables.tf` — not explicitly called out in the plan action, but required for `tofu validate` to pass.
- **Manual modules.json update:** `tofu init` requires the OpenTofu encryption passphrase (1Password Connect unavailable at execution time). Manually updated `.terraform/modules/modules.json` to register `musa.lxc_app` and `musa.lxc_bak` keys pointing to the same LXC module path. This allows `tofu validate` to pass without needing to re-run `tofu init`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] LXC module instances type requires field projection**
- **Found during:** Task 2 (dual LXC module calls)
- **Issue:** The plan's action showed passing `node_role`, `cores`, `memory`, `disk_size` fields through to the LXC module — but `lib/.../lxc/variables.tf` only accepts `vmid`, `node`, `mgmt_ip`, `speed_ip`, `transfer_ip`, `trusted_ip`, `tags`. Passing unknown fields would cause a Terraform type error.
- **Fix:** Added explicit field projection in `local.app_instances` and `local.bak_instances` — each for-expression only extracts the fields the LXC module accepts (`vmid`, `node`, `mgmt_ip`, `transfer_ip`).
- **Files modified:** terraform/main.tf
- **Verification:** `tofu validate` passes
- **Committed in:** `9a7f2bf` (Task 2 commit)

**2. [Rule 3 - Blocking] modules.json needed manual update for tofu validate**
- **Found during:** Task 2 verification (tofu validate)
- **Issue:** Renaming `module "lxc"` to `module "lxc_app"` and `module "lxc_bak"` requires `tofu init` to register the new module keys. `tofu init` requires the OpenTofu encryption passphrase, which is in 1Password Connect (unavailable).
- **Fix:** Manually updated `.terraform/modules/modules.json` to add `musa.lxc_app` and `musa.lxc_bak` entries pointing to the already-cached LXC module directory.
- **Files modified:** terraform/envs/test/.terraform/modules/modules.json
- **Verification:** `tofu validate` passes with no errors
- **Committed in:** Not separately committed (untracked file, gitignored `.terraform/`)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking)
**Impact on plan:** Both fixes required for correctness. No scope creep.

## Issues Encountered

- `tofu init` unavailable without 1Password Connect access (encryption passphrase in `op://Homelab/opentofu/password`). Resolved via manual modules.json update. User will need to run `just test::init` (which reads passphrase via op-read) before running `just test::plan` or `just test::apply`.

## User Setup Required

None — no external service configuration required for this plan. The next deploy step (`just test::apply`) requires 1Password Connect access as normal.

## Next Phase Readiness

- Terraform configuration ready for `just test::init && just test::apply` to provision 3 LXC containers
- Inventory will be auto-generated at `ansible/inventory/test.yaml` after first `tofu apply`
- Multi-group inventory structure (musa, etcd_nodes, patroni_nodes, app_nodes, backup_nodes) is ready for Phase 06 plan 02 and all subsequent HA service phases

---
*Phase: 06-multi-node-infrastructure*
*Completed: 2026-04-28*
