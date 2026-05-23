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
# Provider Configuration
# ============================================================================

provider "proxmox" {
  endpoint  = local.base.proxmox_api_url
  api_token = "${local.base.proxmox_api_token_id}=${local.base.proxmox_api_token_secret}"
  insecure  = true

  ssh {
    agent    = true
    username = "root"
  }
}

# Placeholder — no resources defined yet
