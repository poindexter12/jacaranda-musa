# Phase 6: Multi-Node Infrastructure - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-28
**Phase:** 06-multi-node-infrastructure
**Areas discussed:** Service Placement, Inventory Groups, Resource Sizing, Node Naming & Identity, Existing Node Fate

---

## Service Placement

### App node count

| Option | Description | Selected |
|--------|-------------|----------|
| 2 nodes (1+2) | Twenty server+worker on nodes 1 and 2 only. Node 3 is DB+backup focused. | ✓ |
| All 3 nodes | Every node runs everything including Twenty app. | |
| You decide | Let Claude pick. | |

**User's choice:** 2 nodes (1+2)
**Notes:** None

### Docker Compose templating

| Option | Description | Selected |
|--------|-------------|----------|
| Per-role templates | 2 templates: app-node.yaml.j2 and db-node.yaml.j2. | |
| Single template | One docker-compose.yaml.j2 with Jinja2 conditionals. | |
| You decide | Let Claude pick during planning. | ✓ |

**User's choice:** You decide
**Notes:** Claude's discretion on compose template approach.

### Cross-node networking

| Option | Description | Selected |
|--------|-------------|----------|
| Management VLAN only | All traffic on 192.168.5.0/24. | |
| Separate cluster VLAN | Second NIC for cluster traffic. | ✓ |
| You decide | Let Claude pick. | |

**User's choice:** Dual NIC — management on .5.x, cluster/transfer traffic on .11.x. High-speed .12.x only with explicit user approval.
**Notes:** User clarified: "interfacing binds to .5.x so i would login there. transferring happens on .11. if it needs very high speed, .12.x needs explicit approval."

### Dual NIC confirmation

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, dual NIC | eth0 on .5.x + eth1 on .11.x | ✓ |
| Clarify further | User wants to explain differently. | |

**User's choice:** Yes, dual NIC
**Notes:** None

---

## Inventory Groups

### Inventory generation method

| Option | Description | Selected |
|--------|-------------|----------|
| Terraform local_file | Generate with local_file + templatefile(). Full control. | ✓ |
| Extend LXC module | Add multi-group to shared-libs. Requires PR. | |
| Ansible group_vars | Static inventory file importing generated one. | |

**User's choice:** Not sure — asked for best guess. Claude recommended Terraform local_file.
**Notes:** User said "not sure, best guess?" — Claude recommended local_file approach as best fit for single-project HA needs without touching shared-libs.

### Group layout

| Option | Description | Selected |
|--------|-------------|----------|
| Use research layout | etcd_nodes: all 3, patroni_nodes: all 3, app_nodes: 1+2, backup_nodes: 3. Plus 'musa'. | ✓ |
| Simpler start | Just 'musa' now, add role groups later. | |
| You decide | Let Claude pick. | |

**User's choice:** Use research layout
**Notes:** None

### Host variables

| Option | Description | Selected |
|--------|-------------|----------|
| Inline in inventory | Terraform generates inventory with per-host vars. | ✓ |
| Separate host_vars | Minimal inventory, vars in host_vars/ files. | |
| You decide | Let Claude pick. | |

**User's choice:** Inline in inventory
**Notes:** None

---

## Resource Sizing

### Per-node differentiation

| Option | Description | Selected |
|--------|-------------|----------|
| Differentiate node 3 | Nodes 1+2: app+DB resources. Node 3: fewer cores, less RAM, larger disk. | ✓ |
| Uniform sizing | All 3 nodes identical. | |
| Custom sizing | User has different numbers. | |

**User's choice:** Differentiate node 3
**Notes:** "it can be pretty resource constrained if we need it. we are also talking about a pretty small customer here so it doesn't need to be crazy."

### Configurability

| Option | Description | Selected |
|--------|-------------|----------|
| Per-instance in map | Each instance specifies own resources. | |
| Shared vars + override | Default vars at module level with per-instance overrides. | ✓ |
| You decide | Let Claude pick. | |

**User's choice:** Shared vars + override
**Notes:** None

---

## Node Naming & Identity

### Naming convention

| Option | Description | Selected |
|--------|-------------|----------|
| Numbered: musa-test-{1,2,3} | Simple, matches research. | |
| Role-based: musa-test-{app1,app2,bak} | Names reflect primary role. | ✓ |
| Node-named: musa-test-{joseph,...} | Names include Proxmox node. | |

**User's choice:** Role-based
**Notes:** None

### VMID allocation (first attempt)

| Option | Description | Selected |
|--------|-------------|----------|
| 1180, 1181, 1182 | Reuse 1180 for app1. | ✓ |

**User's choice:** 1180, 1181, 1182
**Notes:** Later revised after "keep old node alive" decision required fresh VMIDs.

### Transfer VLAN IPs

| Option | Description | Selected |
|--------|-------------|----------|
| Same octets: .11.180-182 | Easy mental mapping. | ✓ |
| Different range | User specifies. | |

**User's choice:** Same octets
**Notes:** Later revised to .190-192 to match final VMIDs.

---

## Existing Node Fate

### What happens to old musa-test

| Option | Description | Selected |
|--------|-------------|----------|
| Destroy and recreate | Clean slate, take pg_dump first. | |
| Keep running alongside | Don't touch old LXC. Create new HA cluster alongside. | ✓ |
| Reuse as app1 | Terraform state surgery to adopt existing. | |

**User's choice:** Keep running alongside
**Notes:** None

### Terraform state handling

| Option | Description | Selected |
|--------|-------------|----------|
| Same state, coexist | Expand test/main.tf with both old and new. | |
| Separate TF root | New directory for HA cluster. | |
| You decide | Let Claude pick. | |

**User's choice:** "I don't care about the current state. As soon as this is working all the way, I plan to nuke it. This is transitionary."
**Notes:** Overwrite Terraform state with new 3-node config. Old LXC stays alive on Proxmox but Terraform doesn't manage it anymore. User destroys manually after HA is proven.

### VMID revision

| Option | Description | Selected |
|--------|-------------|----------|
| 1180, 1181, 1182 | Reclaims 1180 (contradicts keeping old alive). | |
| 1190, 1191, 1192 | Jump to .190 range. Clean separation. | ✓ |
| 1181, 1182, 1183 | Adjacent to old 1180. | |

**User's choice:** 1190, 1191, 1192
**Notes:** Clean separation from old 1180. Final allocation: app1=1190/joseph, app2=1191/everette, bak=1192/maxwell.

---

## Claude's Discretion

- Docker Compose templating approach (per-role vs single conditional template)
- Exact resource numbers for test environment nodes
- Terraform `local_file` template structure for inventory

## Deferred Ideas

None — discussion stayed within phase scope
