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
  hub_state_path = "../../../../jacaranda-infra/infrastructure/terraform/terraform.tfstate"
}

locals {
  base = module.base_infra
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

# Placeholder — no resources defined yet
