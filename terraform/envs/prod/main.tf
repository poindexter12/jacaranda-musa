# ============================================================================
# Musa Production Environment (Placeholder)
# ============================================================================
# Production deployment not yet configured.
# When ready, create instance definitions following the test pattern.
#
# Expected allocation:
#   VMID: TBD
#   Node: TBD
#   Mgmt IP: TBD

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

locals {
  infra = yamldecode(file("${path.module}/../../../infra.yaml"))
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

# Placeholder — no resources defined yet
