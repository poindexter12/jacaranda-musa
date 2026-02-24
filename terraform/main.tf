# ============================================================================
# Musa LXC Module
# ============================================================================
# Creates a single LXC container for the Musa Project (Twenty CRM) using the
# shared LXC module. Uses the module's built-in inventory generation since
# there are no per-host variables (no Keepalived, no HA).
#
# The LXC module handles: container creation, SSH host cert signing,
# SSH CA configuration.
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
      source = "Telmate/proxmox"
      # Version controlled by root module lockfile
    }
  }
}

# ============================================================================
# LXC Container (via shared module)
# ============================================================================

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
