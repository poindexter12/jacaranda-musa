# ============================================================================
# Musa Test Environment (single LXC, Proxmox HA-managed)
# ============================================================================
# Single Twenty CRM LXC on joseph, registered with Proxmox HA so it will
# automatically failover to another cluster node (everette, maxwell) if its
# current host goes down. Disk on Ceph so the LXC migrates without data copy.
#
# VMID Allocation: 1190 (4-digit TSSS: 1xxx LXC + IP octet)
# Reference: .claude/skills/vmid-allocation.md
#
# IP Allocation:
#   test.app.musa:   192.168.5.190 / 192.168.11.190 (VMID 1190, joseph initial)

terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.101"
    }
  }
}

# ============================================================================
# Base Infrastructure
# ============================================================================

module "base_infra" {
  source         = "../../../lib/infrastructure/terraform/modules/base-infra"
  hub_state_path = "${path.module}/../../../../jacaranda-infra/infrastructure/terraform/terraform.tfstate"
}

locals {
  base = module.base_infra
}

# ============================================================================
# VMID Allocation Validation
# ============================================================================

module "vmid" {
  source = "../../../lib/infrastructure/terraform/modules/vmid-ranges"
}

# Validate all VMIDs are in LXC range (1001-1254)
check "vmid_allocation" {
  assert {
    condition = alltrue([
      for name, inst in local.musa_instances :
      contains(module.vmid.validate.lxc, inst.vmid)
    ])
    error_message = "One or more VMIDs are outside the LXC allocation range (1001-1254). See .claude/skills/vmid-allocation.md"
  }
}

# ============================================================================
# Provider Configuration
# ============================================================================

provider "proxmox" {
  endpoint  = "https://192.168.5.5:8006/"
  api_token = "${local.base.proxmox_api_token_id}=${local.base.proxmox_api_token_secret}"
  insecure  = true

  ssh {
    agent    = true
    username = "root"
  }
}

# ============================================================================
# Instance Configuration
# ============================================================================

locals {
  env = "test"

  musa_instances = {
    "test.app.musa" = {
      vmid        = 1190
      node        = "joseph"
      mgmt_ip     = "192.168.5.190"
      transfer_ip = "192.168.11.190"
      node_role   = "app"
    }
  }
}

# ============================================================================
# Musa Module
# ============================================================================

module "musa" {
  source = "../.."

  env       = local.env
  instances = local.musa_instances

  ansible_inventory_path = "${path.module}/../../../ansible/inventory/${local.env}.yaml"

  vlans          = local.base.vlans
  ssh_public_key = var.ssh_public_key
  dns_server     = local.base.dns_primary
  ostemplate     = "${local.base.lxc_template_storage}:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  storage        = local.base.storage.ceph.name

  cores     = 4
  memory    = 4096
  disk_size = "20G"

  # Register with Proxmox HA so the LXC restarts on another cluster node
  # if its current host fails. Requires Ceph (already configured above).
  ha_enabled = true
}

# ============================================================================
# Outputs
# ============================================================================

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
