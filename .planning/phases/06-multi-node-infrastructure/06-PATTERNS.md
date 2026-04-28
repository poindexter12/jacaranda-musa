# Phase 6: Multi-Node Infrastructure - Pattern Map

**Mapped:** 2026-04-28
**Files analyzed:** 7 (files to create or modify)
**Analogs found:** 7 / 7

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `terraform/envs/test/main.tf` | config | CRUD | self (current single-node) + `jacaranda-redis/terraform/envs/test/main.tf` | exact |
| `terraform/main.tf` | config | CRUD | self (current) + `jacaranda-shared-libs/.../redis-sentinel/main.tf` | exact |
| `terraform/variables.tf` | config | CRUD | self (current) + `jacaranda-shared-libs/.../redis-sentinel/variables.tf` | exact |
| `terraform/outputs.tf` | config | CRUD | self (current) + `jacaranda-shared-libs/.../redis-sentinel/outputs.tf` | exact |
| `ansible/playbooks/deploy.yaml` | config | request-response | self (current single-group playbook) | role-match |
| `ansible/inventory/group_vars/all.yaml` | config | CRUD | self (current) | exact |
| `test.just` | config | request-response | self (current single-host recipes) | role-match |

## Pattern Assignments

### `terraform/envs/test/main.tf` (config, CRUD)

**Analog:** Self (current) + `jacaranda-redis/terraform/envs/test/main.tf` (dual-NIC + role per instance)

**Current instances map pattern** (lines 70-80):
```hcl
locals {
  env = "test"

  musa_instances = {
    "musa-test" = {
      vmid    = 1180
      node    = "joseph"
      mgmt_ip = "192.168.5.180"
    }
  }
}
```

**Target: Expand to 3 instances with transfer_ip and per-instance role.** Copy from `jacaranda-redis/terraform/envs/test/main.tf` lines 55-68:
```hcl
locals {
  env          = "test"
  service_name = "test-redis"
  vip          = "192.168.11.200" # Same as instance for single-node test

  instances = {
    "test-redis" = {
      vmid        = 1200
      node        = "joseph"
      mgmt_ip     = "192.168.5.200"
      transfer_ip = "192.168.11.200"
      role        = "master" # Single node is always master
    }
  }
}
```

**Base infrastructure + provider pattern** (lines 27-64, keep as-is):
```hcl
module "base_infra" {
  source         = "../../../lib/infrastructure/terraform/modules/base-infra"
  hub_state_path = "${path.module}/../../../../jacaranda-infra/infrastructure/terraform/terraform.tfstate"
}

locals {
  base = module.base_infra
}

provider "proxmox" {
  pm_api_url          = local.base.proxmox_api_url
  pm_api_token_id     = local.base.proxmox_api_token_id
  pm_api_token_secret = local.base.proxmox_api_token_secret
  pm_tls_insecure     = true
}
```

**VMID validation pattern** (lines 40-53, keep as-is):
```hcl
module "vmid" {
  source = "../../../lib/infrastructure/terraform/modules/vmid-ranges"
}

check "vmid_allocation" {
  assert {
    condition = alltrue([
      for name, inst in local.musa_instances :
      contains(module.vmid.validate.lxc, inst.vmid)
    ])
    error_message = "One or more VMIDs are outside the LXC allocation range (1001-1254). See .claude/skills/vmid-allocation.md"
  }
}
```

**Module call pattern** (lines 86-104). Currently passes flat `cores`/`memory`/`disk_size`. Phase 6 needs per-instance overrides (D-12, D-13), meaning these move into the instances map or become module-level defaults with per-instance merge logic.
```hcl
module "musa" {
  source = "../.."

  env       = local.env
  instances = local.musa_instances

  # Infrastructure from base
  vlans              = local.base.vlans
  ssh_public_key     = local.base.ssh_public_key
  ssh_user_ca_pubkey = local.base.ssh_user_ca_pubkey
  dns_server         = local.base.dns_primary
  ostemplate         = "${local.base.lxc_template_storage}:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  storage            = local.base.storage.ceph.name

  # Resources (Twenty CRM needs more than default)
  cores     = 4
  memory    = 4096
  disk_size = "20G"
}
```

**Output forwarding pattern** (lines 110-134, keep structure):
```hcl
output "instances" {
  description = "Musa instances"
  value       = module.musa.instances
}

output "dns_entries" {
  description = "DNS A record entries for Pi-hole"
  value       = module.musa.dns_entries
}

output "cname_entries" {
  description = "CNAME entries for Pi-hole"
  value       = module.musa.cname_entries
}

output "mgmt_ips" {
  description = "Management network IPs for SSH"
  value       = module.musa.mgmt_ips
}

output "ansible_inventory_path" {
  description = "Generated Ansible inventory path"
  value       = module.musa.ansible_inventory_path
}
```

---

### `terraform/main.tf` (config, CRUD)

**Analog:** Self (current) + `jacaranda-shared-libs/.../redis-sentinel/main.tf` (custom inventory generation pattern)

**Current LXC module call** (lines 32-57):
```hcl
module "lxc" {
  source = "../lib/infrastructure/terraform/modules/lxc"

  name = "musa"
  env  = var.env

  instances = var.instances

  # Use module's built-in inventory generation (no per-host vars needed)
  ansible_inventory_path = "${path.module}/../ansible/inventory/${var.env}.yaml"
  ansible_group_name     = "musa"

  # Infrastructure from base
  vlans              = var.vlans
  ssh_public_key     = var.ssh_public_key
  ssh_user_ca_pubkey = var.ssh_user_ca_pubkey
  dns_server         = var.dns_server
  ostemplate         = var.ostemplate
  storage            = var.storage

  # LXC resources
  cores     = var.cores
  memory    = var.memory
  disk_size = var.disk_size
  nesting   = true # Required for Docker-in-LXC
}
```

**Target: Replace built-in inventory with custom `local_file` generation.** The LXC module already supports `transfer_ip` as an optional field in instances (see `lib/.../lxc/variables.tf` line 25: `transfer_ip = optional(string)`). Key change: set `ansible_inventory_path = null` on the LXC module call and generate inventory ourselves.

**Custom inventory pattern from redis-sentinel module** (`jacaranda-shared-libs/.../redis-sentinel/main.tf` lines 131-189):
```hcl
locals {
  # Build host entries with Redis-specific vars
  hosts = {
    for item in local.sorted_instances : item.name => {
      # Connection info (use .lan for SSH cert auth)
      ansible_host = "${item.name}.lan"
      # IPs for internal cluster config
      mgmt_ip     = item.inst.mgmt_ip
      transfer_ip = item.inst.transfer_ip
      # DNS names
      dns_mgmt     = "${item.name}.mgmt"
      dns_transfer = "${item.name}.transfer"
      # Instance metadata
      vmid                = item.inst.vmid
      redis_role          = item.inst.role
      keepalived_state    = local.keepalived_config[item.name].state
      keepalived_priority = local.keepalived_config[item.name].priority
    }
  }

  cluster_name = var.cluster_name != "" ? var.cluster_name : "${var.service_name}-${var.env}"

  # Generate Ansible inventory YAML
  ansible_inventory = {
    all = {
      children = {
        redis_cluster = {
          hosts = local.hosts
        }
      }
      vars = {
        ansible_user            = "root"
        redis_cluster_name      = local.cluster_name
        redis_vip               = var.vip
        redis_vip_prefix_length = local.vip_prefix_length
        redis_vip_dns           = "${var.service_name}.transfer"
        redis_master_host       = local.master_instance.name
        redis_master_ip         = local.master_instance.inst.transfer_ip
        sentinel_quorum         = var.sentinel_quorum
        keepalived_vrrp_id      = var.vrrp_id
      }
    }
  }
}

resource "local_file" "ansible_inventory" {
  count = var.ansible_inventory_path != null ? 1 : 0

  filename        = var.ansible_inventory_path
  content         = "---\n# Auto-generated by Terraform - do not edit manually\n# Regenerate with: tofu apply\n\n${yamlencode(local.ansible_inventory)}"
  file_permission = "0644"
}
```

**Phase 6 adaptation:** Replace `redis_cluster` child group with multiple children per D-10: `musa` (all), `etcd_nodes` (all 3), `patroni_nodes` (all 3), `app_nodes` (app1+app2), `backup_nodes` (bak). Per-host variables include `cluster_ip` (transfer), `node_role`, etc. per D-11.

**LXC module dual-NIC support already exists** (`lib/.../lxc/main.tf` lines 96-105):
```hcl
  # Network - eth2: Transfer (optional)
  dynamic "network" {
    for_each = lookup(each.value, "transfer_ip", null) != null ? [1] : []
    content {
      name   = lookup(each.value, "speed_ip", null) != null ? "eth2" : "eth1"
      bridge = var.vlans["transfer"].bridge
      ip     = "${each.value.transfer_ip}/24"
      gw     = var.primary_network == "transfer" ? var.vlans["transfer"].gateway : null
    }
  }
```

With no `speed_ip`, the transfer NIC will be assigned `eth1` automatically.

**Per-instance resource overrides:** The LXC module currently takes flat `cores`/`memory`/`disk_size` variables applied uniformly. For per-instance sizing (D-12: backup node gets fewer cores, less memory, larger disk), one approach:
- Option A: Call the LXC module once per "resource tier" (e.g., `module "lxc_app"` + `module "lxc_bak"` with different resource params).
- Option B: Extend the instances map object to include optional per-instance `cores`/`memory`/`disk_size` and merge with defaults in the musa module before passing to LXC.

Since the LXC module in shared-libs doesn't support per-instance resource overrides (it uses flat variables), the musa module needs to handle this. The cleanest pattern is Option A (two module calls) or restructuring the musa module to call LXC once per unique resource profile.

---

### `terraform/variables.tf` (config, CRUD)

**Analog:** Self (current) + `jacaranda-shared-libs/.../redis-sentinel/variables.tf` (instances with transfer_ip + role)

**Current instances variable** (lines 9-16):
```hcl
variable "instances" {
  description = "Map of Musa instances to create"
  type = map(object({
    vmid    = number
    node    = string
    mgmt_ip = string # 192.168.5.x - SSH/management
  }))
}
```

**Target: Extend with transfer_ip, node_role, and optional resource overrides.** Pattern from redis-sentinel variables (lines 15-30):
```hcl
variable "instances" {
  description = "Map of Redis instances to create"
  type = map(object({
    vmid        = number
    node        = string
    mgmt_ip     = string
    transfer_ip = string # Client connections, Sentinel gossip, replication, VIP
    role        = string # master, replica
    tags        = optional(list(string), [])
  }))

  validation {
    condition = length([
      for name, inst in var.instances : inst if inst.role == "master"
    ]) == 1
    error_message = "Exactly one instance must have role = 'master'."
  }
}
```

**For Musa, the instances type would extend to:**
```hcl
type = map(object({
  vmid        = number
  node        = string
  mgmt_ip     = string
  transfer_ip = string
  node_role   = string           # "app" or "backup"
  cores       = optional(number) # Override default
  memory      = optional(number)
  disk_size   = optional(string)
}))
```

**New variable needed: `ansible_inventory_path`** -- copied from redis-sentinel pattern:
```hcl
variable "ansible_inventory_path" {
  description = "Path to write Ansible inventory (null = don't generate)"
  type        = string
  default     = null
}
```

---

### `terraform/outputs.tf` (config, CRUD)

**Analog:** Self (current) + `jacaranda-shared-libs/.../redis-sentinel/outputs.tf` (transfer_ips output)

**Current outputs** (lines 1-45, all pass through from `module.lxc`):
```hcl
output "instances" {
  description = "Map of all Musa instances with details"
  value       = module.lxc.instances
}

output "mgmt_ips" {
  description = "Map of hostname to management IP (.5.x)"
  value       = module.lxc.mgmt_ips
}

output "ansible_inventory_path" {
  description = "Path to generated Ansible inventory file"
  value       = module.lxc.ansible_inventory_path
}
```

**New outputs needed:** `transfer_ips` map. Pattern from redis-sentinel outputs (lines 28-31):
```hcl
output "transfer_ips" {
  description = "Transfer IPs for client connections and Sentinel"
  value       = { for name, inst in var.instances : name => inst.transfer_ip }
}
```

**DNS entries:** LXC module already outputs transfer DNS entries when `transfer_ip` is present (`lib/.../lxc/outputs.tf` lines 82-85):
```hcl
    # Transfer network (optional)
    { for name, inst in var.instances : "${name}.transfer" => inst.transfer_ip
      if lookup(inst, "transfer_ip", null) != null
    },
```

**Ansible inventory path changes:** If custom `local_file` is generated in main.tf rather than via LXC module, update this output to reference the local_file resource directly (pattern from redis-sentinel outputs, lines 84-87):
```hcl
output "ansible_inventory_path" {
  description = "Path to generated Ansible inventory file"
  value       = var.ansible_inventory_path != null ? local_file.ansible_inventory[0].filename : null
}
```

**CNAME entries pattern** (keep existing, lines 35-44):
```hcl
output "cname_entries" {
  description = "CNAME entries for Pi-hole (bare => .lan => .mgmt)"
  value = merge(
    # Instance CNAMEs from LXC module (for SSH cert auth)
    module.lxc.cname_entries,
    # Bare name convenience CNAMEs
    {
      for name, inst in var.instances :
      name => "${name}.lan"
    }
  )
}
```

---

### `ansible/playbooks/deploy.yaml` (config, request-response)

**Analog:** Self (current single-group playbook)

**Current playbook** (lines 14-18):
```yaml
- name: Deploy Musa (Twenty CRM)
  hosts: musa
  become: true
  roles:
    - musa
```

**Phase 6 changes:** The playbook `hosts:` directive already targets `musa` group. With multi-group inventory (D-10), `musa` is the "all nodes" group, so the existing playbook structure works for deploying Docker + common setup to all nodes. No structural pattern change needed at this stage -- the HA service roles (etcd, patroni, etc.) will be added in later phases.

However, the playbook may need `serial:` directives or multiple plays targeting different groups in later phases. For Phase 6 (infrastructure only), the current pattern suffices -- all 3 nodes get the same base `musa` role.

---

### `ansible/inventory/group_vars/all.yaml` (config, CRUD)

**Analog:** Self (current)

**Current content** (lines 1-26):
```yaml
---
# Musa Project Group Variables
# Non-secret values only. Secrets injected via justfile deploy recipe.

# Application
app_data_dir: /opt/musa
timezone: America/Denver

# Twenty CRM
twenty_tag: "v1.20.0"
twenty_domain: musa-project-crm-test.joeseymour.io
# Additional hostnames that nginx will accept (experimental custom domain)
twenty_domain_aliases:
  - crm-test.musa-project.org

# Cloudflare Tunnel (locally managed)
cf_tunnel_name: musa-project-crm-test

# SWAG
swag_url: joeseymour.io
swag_subdomain: musa-project-crm-test

# Custom images
backup_tag: "latest"
rollup_tag: "latest"
webhook_tag: "latest"
```

**Phase 6 impact:** Minimal. Per-host variables (cluster_ip, node_role) are generated inline in inventory by Terraform (D-11), not in group_vars. This file remains the single source of truth for application-level shared variables. No new variables needed for Phase 6 infrastructure-only.

---

### `test.just` (config, request-response)

**Analog:** Self (current single-host recipes)

**Current deploy recipe** (lines 88-107):
```bash
deploy:
    #!/usr/bin/env bash
    set -euo pipefail
    just test::rollback-prep
    cd ansible
    mkdir -p logs
    export ANSIBLE_LOG_PATH="logs/ansible-$(date +%Y%m%d-%H%M%S).log"
    printf '%b-> Deploying Musa (test)%b\n' '{{ CYAN }}' '{{ NC }}'
    ANSIBLE_CONFIG=ansible.cfg {{ uv_run }} ansible-playbook \
        {{ ansible_verbose }} \
        -i inventory/test.yaml \
        playbooks/deploy.yaml \
        -e "cf_tunnel_password=$(secret-read 'op://Homelab/musa-project-crm-test/cf_tunnel_password')" \
        # ... more -e flags ...
    printf '%b Done (test)%b\n' '{{ GREEN }}' '{{ NC }}'
```

**Current validate recipe** (lines 131-172) -- hardcodes `host="musa-test"` (single host):
```bash
validate: verify
    #!/usr/bin/env bash
    set -euo pipefail
    host="musa-test"
    # ... checks against single host ...
```

**Phase 6 changes:** `validate`, `verify`, `logs`, `rollback-prep`, `rollback` all hardcode `host="musa-test"`. These need to iterate over 3 hosts: `musa-test-app1`, `musa-test-app2`, `musa-test-bak`. The `deploy` recipe's ansible-playbook call doesn't need structural changes (Ansible handles multi-host from inventory), but the shell-based validation recipes need loops.

---

## Shared Patterns

### LXC Module Consumption
**Source:** `terraform/main.tf` (current pattern) + `lib/.../lxc/variables.tf`
**Apply to:** `terraform/main.tf`, `terraform/envs/test/main.tf`

The LXC module already supports `transfer_ip` as optional in its instances object type. No module modification needed. Pass `transfer_ip` in each instance entry and the module auto-creates eth1 on the transfer VLAN bridge.

### Custom Inventory Generation via `local_file` + `yamlencode`
**Source:** `jacaranda-shared-libs/.../redis-sentinel/main.tf` lines 176-189
**Apply to:** `terraform/main.tf` (new `local_file` resource + inventory locals)

```hcl
resource "local_file" "ansible_inventory" {
  count = var.ansible_inventory_path != null ? 1 : 0

  filename        = var.ansible_inventory_path
  content         = "---\n# Auto-generated by Terraform - do not edit manually\n# Regenerate with: tofu apply\n\n${yamlencode(local.ansible_inventory)}"
  file_permission = "0644"
}
```

### Multi-Group Inventory Structure
**Source:** `jacaranda-shared-libs/.../redis-sentinel/main.tf` lines 153-173 (single group) adapted for multi-group
**Apply to:** `terraform/main.tf` locals block

For D-10, the inventory structure should use multiple `children` groups. The `yamlencode` approach from redis-sentinel works but needs multiple children:

```hcl
local.ansible_inventory = {
  all = {
    children = {
      musa         = { hosts = <all 3> }
      etcd_nodes   = { hosts = <all 3> }
      patroni_nodes = { hosts = <all 3> }
      app_nodes    = { hosts = <app1, app2> }
      backup_nodes = { hosts = <bak> }
    }
  }
}
```

### Per-Host Variables in Inventory
**Source:** `jacaranda-shared-libs/.../redis-sentinel/main.tf` lines 134-149
**Apply to:** Inventory generation in `terraform/main.tf`

Redis-sentinel embeds per-host variables (role, keepalived state/priority, IPs) inline:
```hcl
hosts = {
  for item in local.sorted_instances : item.name => {
    ansible_host = "${item.name}.lan"
    mgmt_ip      = item.inst.mgmt_ip
    transfer_ip  = item.inst.transfer_ip
    vmid         = item.inst.vmid
    redis_role   = item.inst.role
    # ... more per-host vars ...
  }
}
```

### Terraform File Header Comments
**Source:** `terraform/envs/test/main.tf` lines 1-11
**Apply to:** All modified terraform files

```hcl
# ============================================================================
# Musa Test Environment (3-Node HA Cluster)
# ============================================================================
# 3 LXCs across joseph, everette, maxwell for Twenty CRM HA.
#
# VMID Allocation: 1190-1192 (4-digit TSSS: 1xxx LXC + IP octet)
#
# IP Allocation:
#   musa-test-app1:  192.168.5.190 / 192.168.11.190 (VMID 1190, joseph)
#   musa-test-app2:  192.168.5.191 / 192.168.11.191 (VMID 1191, everette)
#   musa-test-bak:   192.168.5.192 / 192.168.11.192 (VMID 1192, maxwell)
```

### Section-Separated HCL Layout
**Source:** All existing terraform files in this repo
**Apply to:** All modified terraform files

```hcl
# ============================================================================
# Section Name
# ============================================================================
```

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| (none) | | | All files have strong analogs in the codebase or sibling repos |

## Key Constraint: LXC Module Does Not Support Per-Instance Resources

The shared LXC module (`lib/.../lxc/main.tf` lines 63-64) applies `var.cores` and `var.memory` uniformly to all instances:
```hcl
  cores  = var.cores
  memory = var.memory
```

Decision D-12 requires the backup node to have fewer cores, less memory, and larger disk. Since the shared module cannot be modified (agent boundary), the musa module needs one of:

1. **Two LXC module calls** -- `module "lxc_app"` (2 app instances, 4 cores, 4096 MB, 20G) and `module "lxc_bak"` (1 backup instance, 2 cores, 2048 MB, 40G). Both share the same `vlans`, `ssh_*`, etc. Inventory is generated custom regardless.
2. **Single call with highest resources** -- waste on backup node but simpler. Then override container resources via Ansible/pct after creation.

Option 1 is the cleanest -- it follows the existing pattern of calling the LXC module with uniform resources, just doing it twice with different resource tiers. The redis-sentinel module avoids this problem because all Redis nodes have identical resources.

## Metadata

**Analog search scope:** `jacaranda-musa/terraform/`, `jacaranda-musa/ansible/`, `jacaranda-shared-libs/infrastructure/terraform/modules/lxc/`, `jacaranda-shared-libs/infrastructure/terraform/modules/redis-sentinel/`, `jacaranda-redis/terraform/envs/test/`, `jacaranda-pihole/terraform/`
**Files scanned:** 25+
**Pattern extraction date:** 2026-04-28
