# Musa Project — Twenty CRM Service
#
# Single-node LXC with SWAG + Cloudflare Tunnel running Twenty CRM.
#
# Usage: just <module>::<recipe>
#
# Examples:
#   just test::full              # Create LXC + deploy
#   just test::validate          # Check service health
#   just check-secrets           # Verify 1Password items exist

import '../../lib/infrastructure/just/styles.just'
import '../../lib/infrastructure/just/secrets.just'

# Module declarations
mod test
mod prod

# Show available recipes
@_default:
    just --list

# ============================================================================
# Cross-Environment Utilities
# ============================================================================

# Verify 1Password items exist
check-secrets:
    #!/usr/bin/env bash
    printf '%b--- Checking 1Password items ---%b\n' '{{ BOLD }}' '{{ NC }}'
    items=(
        "Homelab/musa-project-crm-test/cf_tunnel_token"
        "Homelab/musa-project-crm-test/pg_password"
        "Homelab/musa-project-crm-test/app_secret"
        "Homelab/cloudflare/api_token"
        "Homelab/cloudflare/zone_id"
        "Homelab/cloudflare/account_id"
        "Homelab/github/pat"
    )
    for item in "${items[@]}"; do
        echo "Checking: op://$item"
        if {{ op_read }} "op://$item" > /dev/null 2>&1; then
            printf '%b  OK %s%b\n' '{{ GREEN }}' "$item" '{{ NC }}'
        else
            printf '%b  MISSING %s%b\n' '{{ RED }}' "$item" '{{ NC }}'
        fi
    done
