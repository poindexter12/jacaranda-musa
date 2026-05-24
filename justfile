# Musa Project — Twenty CRM Service (single LXC, Proxmox HA-managed)
#
# 1 Twenty CRM LXC with Proxmox HA failover across the cluster (joseph,
# everette, maxwell). Disk on Ceph so the LXC migrates without data copy.
#
# Usage: just <module>::<recipe>
#
# Examples:
#   just test::full              # Create LXC + deploy
#   just test::validate          # Check service health
#   just check-secrets           # Verify 1Password items exist

set allow-duplicate-variables := true

# styles.just is optional — if the lib/ submodule is initialized it provides
# real ANSI codes; otherwise _styles-fallback.just supplies blanks so recipes
# still parse. First import wins under allow-duplicate-variables.
import? 'lib/infrastructure/just/styles.just'
import '_styles-fallback.just'
import 'lib/infrastructure/just/secrets.just'

# Module declarations
mod test
mod prod

# Show available recipes
@_default:
    just --list

# ============================================================================
# Cross-Environment Utilities
# ============================================================================

# Upgrade OpenTofu providers to latest versions
upgrade:
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b→ Upgrading OpenTofu providers%b\n' '{{ CYAN }}' '{{ NC }}'
    encryption_pw=$(secret-read 'op://Homelab/opentofu/password')
    for env in test prod; do
        printf '%b  → %s%b\n' '{{ YELLOW }}' "$env" '{{ NC }}'
        tofu -chdir=terraform/envs/$env init -upgrade -var="encryption_passphrase=$encryption_pw"
    done
    printf '%b✓ Provider upgrade complete%b\n' '{{ GREEN }}' '{{ NC }}'

# Verify 1Password items exist (shows which backend served each read)
check-secrets mode="auto":
    #!/usr/bin/env bash
    printf '%b--- Checking 1Password items (mode: {{ mode }}) ---%b\n' '{{ BOLD }}' '{{ NC }}'
    export SECRET_READ_DEBUG=1
    case "{{ mode }}" in
        auto)    ;;                                    # Connect first, fall back to local op
        connect) ;;                                    # Same as auto; left explicit for symmetry
        local)   export SECRET_READ_DISABLE_CONNECT=1 ;;  # Force local op CLI
        *) printf '%bUnknown mode: {{ mode }} (use auto|connect|local)%b\n' '{{ RED }}' '{{ NC }}'; exit 1 ;;
    esac
    items=(
        "Homelab/musa-project-crm-test/cf_tunnel_token"
        "Homelab/musa-project-crm-test/pg_password"
        "Homelab/musa-project-crm-test/app_secret"
        "Homelab/musa-project-crm-test/encryption_key"
        "Homelab/musa-project-crm-test/cf_api_token"
        "Homelab/cloudflare/zone_id"
        "Homelab/cloudflare/account_id"
        "Homelab/github/pat"
        "Homelab/Jacaranda Proxmox Deploy/api token"
        "Homelab/musa-project-test/public key"
        "Homelab/opentofu/password"
    )
    for item in "${items[@]}"; do
        # Capture stderr only: stdout (the secret value) is discarded; stderr
        # holds the SECRET_READ_DEBUG=1 line telling us which backend won.
        if stderr=$(secret-read "op://$item" 2>&1 >/dev/null); then
            if grep -q 'local op' <<< "$stderr"; then
                backend='local'
            else
                backend='connect'
            fi
            printf '%b  OK %s %b(%s)%b\n' '{{ GREEN }}' "$item" '{{ CYAN }}' "$backend" '{{ NC }}'
        else
            printf '%b  MISSING %s%b\n' '{{ RED }}' "$item" '{{ NC }}'
        fi
    done
