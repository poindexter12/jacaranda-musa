# Phase 6: Multi-Node Infrastructure - Context

**Gathered:** 2026-04-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Provision 3 LXC containers across 3 Proxmox nodes (joseph, everette, maxwell) with dual-NIC networking and generate multi-group Ansible inventory. This is the foundation phase for v2.0 Multi-Node HA. Does NOT include deploying any HA services (etcd, Patroni, Redis, app) — only the infrastructure layer.

</domain>

<decisions>
## Implementation Decisions

### Service Placement
- **D-01:** Each LXC runs a Docker Compose stack containing all services for that node's role (not split across separate LXCs)
- **D-02:** App instances (Twenty server + worker + SWAG + cloudflared) on 2 nodes only: musa-test-app1 and musa-test-app2
- **D-03:** Node 3 (musa-test-bak) is DB + backup focused: Patroni, etcd, Redis replica, Sentinel, pgBackRest repo host, pg_dump GFS cron
- **D-04:** All 3 nodes run etcd, Patroni (PG), Redis, and Sentinel

### Networking
- **D-05:** Dual NIC per LXC: eth0 on management VLAN (192.168.5.x) for SSH/interfacing, eth1 on transfer VLAN (192.168.11.x) for cluster traffic
- **D-06:** Cluster traffic (etcd, PG replication, Redis Sentinel) binds to .11.x addresses
- **D-07:** Management/SSH traffic on .5.x addresses
- **D-08:** No high-speed VLAN (.12.x) unless explicitly approved by user

### Inventory Generation
- **D-09:** Use Terraform `local_file` + `templatefile()` to generate multi-group Ansible inventory (bypass LXC module's built-in single-group generator)
- **D-10:** Ansible groups from day one: `musa` (all nodes), `etcd_nodes` (all 3), `patroni_nodes` (all 3), `app_nodes` (app1 + app2), `backup_nodes` (bak)
- **D-11:** Per-host variables (cluster_ip, node_role, etc.) inline in generated inventory, not in separate host_vars files

### Resource Sizing
- **D-12:** Node 3 (backup) differentiated: fewer cores, less memory, larger disk than app nodes
- **D-13:** Shared default variables for cores/memory/disk at module level with per-instance overrides in the instances map
- **D-14:** Small footprint for test environment (CRM workload is small customer scale)

### Node Naming & Identity
- **D-15:** Role-based naming: `musa-test-app1`, `musa-test-app2`, `musa-test-bak`
- **D-16:** VMIDs: 1190 (app1/joseph), 1191 (app2/everette), 1192 (bak/maxwell)
- **D-17:** Management IPs: 192.168.5.190, .191, .192
- **D-18:** Transfer IPs: 192.168.11.190, .191, .192 (same last octet as management)

### Existing Node Transition
- **D-19:** Old musa-test (VMID 1180) stays alive on Proxmox — user destroys manually after HA is proven
- **D-20:** Terraform state gets overwritten with new 3-node config (fresh `tofu init`). No state migration needed.
- **D-21:** New HA cluster uses VMIDs 1190-1192 to avoid collision with old 1180
- **D-22:** Data migration from old node to Patroni cluster is Phase 7 concern, not Phase 6

### Docker Compose Templating
- **D-23:** Claude's discretion: per-role templates vs single conditional template — decide during planning based on complexity

</decisions>

<specifics>
## Specific Ideas

- Node 3 can be "pretty resource constrained" — small customer, doesn't need to be big
- User wants to manually destroy old musa-test after HA is proven end-to-end
- Same last octet pattern across VLANs for easy mental mapping

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Architecture Research
- `.planning/research/architecture.md` — Node allocation, service placement diagram, cross-LXC networking approach, IP allocation, Terraform/Ansible change analysis

### Existing Terraform Patterns
- `terraform/main.tf` — Current LXC module usage (single instance, `for_each` over instances map)
- `terraform/variables.tf` — Current variable definitions (instances map type, resource vars)
- `terraform/envs/test/main.tf` — Current test environment config (single node, base-infra usage, VMID validation)
- `terraform/outputs.tf` — Current outputs (dns_entries, cname_entries, mgmt_ips, inventory path)

### Shared Modules
- `lib/infrastructure/terraform/modules/lxc` — LXC module (container creation, SSH cert signing, inventory generation)
- `lib/infrastructure/terraform/modules/base-infra` — Base infrastructure outputs (Proxmox API, VLANs, SSH keys, DNS, storage)
- `lib/infrastructure/terraform/modules/vmid-ranges` — VMID allocation validation

### Ansible Patterns
- `ansible/playbooks/deploy.yaml` — Current deploy playbook (single role, single group)
- `ansible/inventory/group_vars/all.yaml` — Current shared variables
- `ansible/roles/musa/` — Current musa role (Docker install, templates, health checks)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **LXC module** (`lib/.../modules/lxc`): Already supports `for_each` over instances map with per-instance node/vmid/ip. Needs dual-NIC extension or workaround.
- **base-infra module**: Provides VLAN config map including transfer VLAN (.11.x). Already consumed in test/main.tf.
- **VMID validation**: `vmid-ranges` module validates LXC range (1001-1254). Will work for 1190-1192.

### Established Patterns
- **Instances map**: `map(object({ vmid, node, mgmt_ip }))` — needs extension to include `transfer_ip` and resource overrides
- **base-infra consumption**: `local.base = module.base_infra` pattern for accessing infrastructure values
- **Output forwarding**: dns_entries, cname_entries, mgmt_ips passed through from LXC module

### Integration Points
- **Ansible inventory**: Currently generated by LXC module at `ansible/inventory/${var.env}.yaml`. Phase 6 replaces this with custom `local_file` generation.
- **DNS outputs**: Hub repository consumes `dns_entries` and `cname_entries` for Pi-hole. 3 nodes = 3x DNS entries.
- **SSH host certs**: LXC module handles signing. 3 nodes = 3 cert signing operations.

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-multi-node-infrastructure*
*Context gathered: 2026-04-28*
