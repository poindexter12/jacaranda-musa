# ============================================================================
# Musa Test Environment (Single Node)
# ============================================================================
# Single LXC on joseph running Twenty CRM with SWAG + Cloudflare Tunnel.
#
# VMID Allocation: 1180 (4-digit TSSS: 1xxx LXC + IP octet .180)
# Reference: .claude/skills/vmid-allocation.md
#
# IP Allocation:
#   musa-test: 192.168.5.180 (VMID 1180, mgmt only)

terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "= 3.0.2-rc07"
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
  pm_api_url          = local.base.proxmox_api_url
  pm_api_token_id     = local.base.proxmox_api_token_id
  pm_api_token_secret = local.base.proxmox_api_token_secret
  pm_tls_insecure     = true
}

# ============================================================================
# Instance Configuration
# ============================================================================

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

# ============================================================================
# Musa Module
# ============================================================================

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
