# Phase 7: Resource Registration & Terraform Prep - Context

**Gathered:** 2026-05-02
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

All musa resource allocations are formalized in the network registry and Terraform LXC module calls no longer depend on CA cert signing. Covers REG-01, REG-02, REG-03, PROV-01.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase. Use ROADMAP phase goal, success criteria, and codebase conventions to guide decisions.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `terraform/main.tf` — Musa module with dual LXC calls (lxc_app, lxc_bak), passes `ssh_user_ca_pubkey` to both
- `terraform/variables.tf` — Declares `ssh_user_ca_pubkey` variable (line 55-58)
- `terraform/envs/test/main.tf` — Test env passes `local.base.ssh_user_ca_pubkey` to musa module
- `lib/infrastructure/terraform/modules/lxc/main.tf` — Shared LXC module with `null_resource.sign_host_cert` and CA sshd config
- `lib/infrastructure/terraform/modules/lxc/sign-host-cert.sh` — Host cert signing script

### Established Patterns
- Base infrastructure consumed via `base-infra` module (never terraform_remote_state)
- Shared modules in `lib/` submodule at v1.4.0 — NOT modifiable from this repo
- Registry allocations formalized via jacaranda-inventory (services/musa.yaml)
- VMID allocation uses 4-digit TSSS pattern

### Integration Points
- LXC module `ssh_user_ca_pubkey` variable must become optional or skippable — shared module change needed in jacaranda-shared-libs
- Registry entries go in external jacaranda-inventory repo
- `terraform/envs/test/main.tf` passes CA pubkey from base_infra — needs removal

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase. Refer to ROADMAP phase description and success criteria.

Key constraint: shared LXC module in `lib/` cannot be modified from this repo. If CA cert signing needs to be made optional in the module, that's a jacaranda-shared-libs change.

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase.

</deferred>
