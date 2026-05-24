# ============================================================================
# Musa Test Environment (single LXC, Proxmox HA-managed)
# ============================================================================
# Single Twenty CRM LXC on joseph, registered with Proxmox HA so it will
# automatically failover to another cluster node (everette, maxwell) if its
# current host goes down. Disk on Ceph so the LXC migrates without data copy.
#
# VMID Allocation: 1095 (4-digit TSSS: 1xxx LXC + IP octet)
# Reference: .claude/skills/vmid-allocation.md
#
# IP Allocation:
#   test.app.musa:   192.168.5.95 / 192.168.11.95 (VMID 1095, joseph initial)

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
# Infrastructure topology
# ============================================================================
# Self-contained: reads musa's own infra.yaml (Proxmox/network/storage) and the
# jacaranda-inventory registry for DNS server allocations. No dependency on the
# former jacaranda-infra hub state.

locals {
  infra    = yamldecode(file("${path.module}/../../../infra.yaml"))
  dns_yaml = yamldecode(file("${path.module}/../../../../jacaranda-inventory/data/services/dns.yaml"))

  # Bootstrap resolver: prod primary Pi-hole on the mgmt VLAN. Hostname looked
  # up in the registry; IP synthesised from infra.yaml's VLAN network + the
  # registry's host octet so a registry move stays consistent.
  dns_primary_alloc = one([
    for alloc in local.dns_yaml.allocations :
    alloc if alloc.vlan == "mgmt" && alloc.hostname == "prod.primary.standard.dns"
  ])
  dns_primary = "${local.infra.vlans["mgmt"].network}.${local.dns_primary_alloc.host}"
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
  endpoint  = var.proxmox_endpoint
  api_token = "${local.infra.proxmox.api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = local.infra.proxmox.tls_insecure

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
      vmid        = 1095
      node        = "joseph"
      mgmt_ip     = "192.168.5.95"
      transfer_ip = "192.168.11.95"
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

  vlans          = local.infra.vlans
  ssh_public_key = var.ssh_public_key
  dns_server     = local.dns_primary
  ostemplate     = "${local.infra.lxc_template_storage}:vztmpl/${local.infra.lxc_template}"
  storage        = local.infra.storage.ceph.name

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
