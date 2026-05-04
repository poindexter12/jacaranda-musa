# ============================================================================
# Musa LXC Module (3-Node HA Cluster)
# ============================================================================
# Creates LXC containers for the Musa Project (Twenty CRM HA) using the shared
# LXC module. Two module calls handle different resource tiers:
#   - lxc_app: App nodes (4 cores, 4096 MB, 20G) — per D-12, D-13
#   - lxc_bak: Backup node (2 cores, 2048 MB, 40G) — per D-12
#
# Custom multi-group inventory generated via local_file (per D-09).
# The LXC module's built-in inventory is disabled (ansible_inventory_path=null).
#
# VMID Allocation: 1190-1192 (4-digit TSSS: 1xxx LXC + IP octet)
# IP Allocation:
#   test.app1.app.musa:     192.168.5.190 / 192.168.11.190 (VMID 1190, joseph)
#   test.app2.app.musa:     192.168.5.191 / 192.168.11.191 (VMID 1191, everette)
#   test.bak.backup.musa:   192.168.5.192 / 192.168.11.192 (VMID 1192, maxwell)

terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
      # Version controlled by root module lockfile
    }
  }
}

# ============================================================================
# Instance Tier Split
# ============================================================================
# The shared LXC module applies resource vars uniformly to all instances.
# Per D-12/D-13, the backup node needs different resources than app nodes.
# Solution: two module calls with different resource params.
#
# The LXC module's instances type accepts: vmid, node, mgmt_ip, transfer_ip
# (plus speed_ip, trusted_ip, tags). Musa-specific fields (node_role, cores,
# memory, disk_size) are stripped before passing to the LXC module.

locals {
  # Split instances by role for different resource tiers
  app_instances = {
    for name, inst in var.instances : name => {
      vmid        = inst.vmid
      node        = inst.node
      mgmt_ip     = inst.mgmt_ip
      transfer_ip = inst.transfer_ip
    } if inst.node_role == "app"
  }

  bak_instances = {
    for name, inst in var.instances : name => {
      vmid        = inst.vmid
      node        = inst.node
      mgmt_ip     = inst.mgmt_ip
      transfer_ip = inst.transfer_ip
    } if inst.node_role == "backup"
  }

  # Extract backup node resource overrides (there is exactly 1 backup node)
  bak_node = one([for name, inst in var.instances : inst if inst.node_role == "backup"])

  bak_cores     = coalesce(local.bak_node.cores, var.cores)
  bak_memory    = coalesce(local.bak_node.memory, var.memory)
  bak_disk_size = coalesce(local.bak_node.disk_size, var.disk_size)
}

# ============================================================================
# LXC Containers — App Tier (via shared module)
# ============================================================================

module "lxc_app" {
  source = "../lib/infrastructure/terraform/modules/lxc"

  name = "musa"
  env  = var.env

  instances = local.app_instances

  # Disable built-in inventory — we generate custom multi-group inventory below (per D-09)
  ansible_inventory_path = null

  # Infrastructure from base
  vlans              = var.vlans
  ssh_public_key     = var.ssh_public_key
  dns_server         = var.dns_server
  ostemplate         = var.ostemplate
  storage            = var.storage

  # App tier resources (per D-13 defaults)
  cores     = var.cores
  memory    = var.memory
  disk_size = var.disk_size
  nesting   = true # Required for Docker-in-LXC
}

# ============================================================================
# LXC Containers — Backup Tier (via shared module)
# ============================================================================

module "lxc_bak" {
  source = "../lib/infrastructure/terraform/modules/lxc"

  name = "musa"
  env  = var.env

  instances = local.bak_instances

  # Disable built-in inventory
  ansible_inventory_path = null

  # Infrastructure from base
  vlans              = var.vlans
  ssh_public_key     = var.ssh_public_key
  dns_server         = var.dns_server
  ostemplate         = var.ostemplate
  storage            = var.storage

  # Backup tier resources — fewer cores, less memory, larger disk (per D-12)
  cores     = local.bak_cores
  memory    = local.bak_memory
  disk_size = local.bak_disk_size
  nesting   = true # Required for Docker-in-LXC
}

# ============================================================================
# Custom Multi-Group Ansible Inventory (per D-09)
# ============================================================================
# Replaces LXC module's single-group inventory with role-based groups.
# Groups per D-10: musa (all), etcd_nodes (all 3), patroni_nodes (all 3),
# app_nodes (app1+app2), backup_nodes (bak).
# Per-host vars inline per D-11.

locals {
  # Build per-host variable maps (per D-11)
  inventory_hosts = {
    for name, inst in var.instances : name => {
      ansible_host = "${name}.lan"
      mgmt_ip      = inst.mgmt_ip
      transfer_ip  = inst.transfer_ip
      node_role    = inst.node_role
      vmid         = inst.vmid
    }
  }

  # Group membership (per D-10)
  app_host_names    = [for name, inst in var.instances : name if inst.node_role == "app"]
  backup_host_names = [for name, inst in var.instances : name if inst.node_role == "backup"]

  # Build group host maps
  app_hosts = {
    for name in local.app_host_names : name => local.inventory_hosts[name]
  }
  backup_hosts = {
    for name in local.backup_host_names : name => local.inventory_hosts[name]
  }

  # Generate Ansible inventory YAML structure
  ansible_inventory = {
    all = {
      children = {
        musa = {
          hosts = local.inventory_hosts
        }
        etcd_nodes = {
          hosts = local.inventory_hosts
        }
        patroni_nodes = {
          hosts = local.inventory_hosts
        }
        app_nodes = {
          hosts = local.app_hosts
        }
        backup_nodes = {
          hosts = local.backup_hosts
        }
      }
      vars = {
        ansible_user = "root"
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
