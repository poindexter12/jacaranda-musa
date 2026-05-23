# Musa Project — Test Environment (single LXC, Proxmox HA-managed)
#
# 1 LXC on joseph (initial placement), failover to any cluster node via Proxmox HA:
#   test.app.musa: VMID 1190, 192.168.5.190
#
# Usage: just test::<recipe>
#
# Examples:
#   just test::apply         # Create LXC (+ register with Proxmox HA)
#   just test::deploy        # Deploy services
#   just test::full          # Apply + wait + deploy
#   just test::validate      # Check service health

import 'lib/infrastructure/just/terraform.just'
import 'lib/infrastructure/just/ansible.just'

# Hostname for SSH / health checks. Change here if the LXC is renamed.
musa_host := "test.app.musa"

# Show available recipes for this module
@_default:
    just --list test

# ============================================================================
# Terraform Operations
# ============================================================================

# SSH key injected via TF_VAR — Terraform reads TF_VAR_ssh_public_key automatically
export TF_VAR_ssh_public_key := `op-read 'op://Homelab/musa-project-test/public key'`

# Initialize terraform
init: (tf-init "test")

# Plan infrastructure changes
plan: (tf-plan "test")

# Apply infrastructure changes
[confirm("Create/update Musa test LXC container?")]
apply: (tf-apply "test")

# Destroy infrastructure
[confirm("Destroy Musa test LXC container? This is DANGEROUS!")]
destroy: (tf-destroy "test")

# ============================================================================
# Rollback
# ============================================================================

# Save current config as rollback point (called before deploy)
[private]
rollback-prep:
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b-> Saving rollback snapshot%b\n' '{{ CYAN }}' '{{ NC }}'
    ssh -o BatchMode=yes -o ConnectTimeout=5 root@{{ musa_host }}.lan "cd /opt/musa && \
        cp -f docker-compose.yaml docker-compose.yaml.bak 2>/dev/null && \
        cp -f .env .env.bak 2>/dev/null" 2>/dev/null || true

# Rollback to previous deployment
[confirm("Roll back Musa test to previous deployment?")]
rollback:
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== Rolling back Musa (test) ===%b\n' '{{ BOLD }}' '{{ NC }}'

    if ! ssh -o BatchMode=yes root@{{ musa_host }}.lan "test -f /opt/musa/docker-compose.yaml.bak" 2>/dev/null; then
        printf '%b  SKIP: No rollback snapshot on {{ musa_host }}%b\n' '{{ YELLOW }}' '{{ NC }}'
        exit 0
    fi

    ssh -o BatchMode=yes root@{{ musa_host }}.lan "cd /opt/musa && \
        cp -f docker-compose.yaml.bak docker-compose.yaml && \
        cp -f .env.bak .env"
    printf '%b  Restored config from snapshot%b\n' '{{ GREEN }}' '{{ NC }}'

    ssh -o BatchMode=yes root@{{ musa_host }}.lan "cd /opt/musa && docker compose up -d --force-recreate" 2>/dev/null || true

    printf '%b  Waiting 30s for services to start...%b\n' '{{ CYAN }}' '{{ NC }}'
    sleep 30
    printf '%b  Rollback complete — run just test::validate to check health%b\n' '{{ GREEN }}' '{{ NC }}'

# ============================================================================
# Ansible Operations
# ============================================================================

# Deploy Musa services
deploy:
    #!/usr/bin/env bash
    set -euo pipefail
    just test::rollback-prep
    cd ansible
    mkdir -p logs
    export ANSIBLE_LOG_PATH="logs/ansible-$(date +%Y%m%d-%H%M%S).log"
    printf '%b-> Deploying Musa (test)%b\n' '{{ CYAN }}' '{{ NC }}'
    ANSIBLE_CONFIG=ansible.cfg {{ uv_run }} ansible-playbook \
        {{ ansible_verbose }} \
        -i inventory/test.yaml \
        playbooks/deploy.yaml \
        -e "cf_tunnel_password=$(secret-read 'op://Homelab/musa-project-crm-test/cf_tunnel_password')" \
        -e "cf_api_token=$(secret-read 'op://Homelab/musa-project-crm-test/cf_api_token')" \
        -e "cf_zone_id=$(secret-read 'op://Homelab/cloudflare/zone_id')" \
        -e "cf_account_id=$(secret-read 'op://Homelab/cloudflare/account_id')" \
        -e "pg_password=$(secret-read 'op://Homelab/musa-project-crm-test/pg_password')" \
        -e "app_secret=$(secret-read 'op://Homelab/musa-project-crm-test/app_secret')" \
        -e "ghcr_pat=$(secret-read 'op://Homelab/github/pat')"
    printf '%b Done (test)%b\n' '{{ GREEN }}' '{{ NC }}'

# ============================================================================
# Validation
# ============================================================================

# Preflight: DNS and SSH connectivity
[private]
verify:
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== Verify test ===%b\n' '{{ BOLD }}' '{{ NC }}'

    echo "--- DNS ---"
    printf '{{ musa_host }}.lan: '
    dig +short {{ musa_host }}.lan || echo "FAIL"

    echo "--- SSH ---"
    printf '{{ musa_host }}.lan: '
    ssh -o ConnectTimeout=5 -o BatchMode=yes root@{{ musa_host }}.lan hostname 2>/dev/null || echo "FAIL"

# Validate deployment health
validate: verify
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== Validate test (Musa) ===%b\n' '{{ BOLD }}' '{{ NC }}'
    printf '%b--- {{ musa_host }}.lan ---%b\n' '{{ BOLD }}' '{{ NC }}'

    # Docker daemon
    printf '  Docker: '
    if ssh -o BatchMode=yes root@{{ musa_host }}.lan "docker info" >/dev/null 2>&1; then
        printf '%b OK%b\n' '{{ GREEN }}' '{{ NC }}'
    else
        printf '%b FAIL%b\n' '{{ RED }}' '{{ NC }}'
    fi

    # Docker Compose plugin
    printf '  Compose: '
    if ssh -o BatchMode=yes root@{{ musa_host }}.lan "docker compose version" >/dev/null 2>&1; then
        printf '%b OK%b\n' '{{ GREEN }}' '{{ NC }}'
    else
        printf '%b FAIL%b\n' '{{ RED }}' '{{ NC }}'
    fi

    # Docker containers (show whatever is running)
    running=$(ssh -o BatchMode=yes root@{{ musa_host }}.lan "docker ps --format '{{ '{{' }}.Names{{ '}}' }}'" 2>/dev/null || true)
    if [ -n "$running" ]; then
        echo "  Containers:"
        echo "$running" | while read -r c; do
            printf '%b    OK %s running%b\n' '{{ GREEN }}' "$c" '{{ NC }}'
        done
    else
        printf '  Containers: %b(none running)%b\n' '{{ YELLOW }}' '{{ NC }}'
    fi

# ============================================================================
# Logs
# ============================================================================

# View container logs
logs:
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== {{ musa_host }}.lan ===%b\n' '{{ BOLD }}' '{{ NC }}'
    containers=$(ssh -o BatchMode=yes root@{{ musa_host }}.lan "docker ps --format '{{ '{{' }}.Names{{ '}}' }}'" 2>/dev/null || true)
    if [ -n "$containers" ]; then
        echo "$containers" | while read -r container; do
            printf '%b--- %s ---%b\n' '{{ CYAN }}' "$container" '{{ NC }}'
            ssh -o BatchMode=yes root@{{ musa_host }}.lan "docker logs $container --tail=5" 2>/dev/null || echo "  not reachable"
        done
    else
        printf '  %b(no containers running)%b\n' '{{ YELLOW }}' '{{ NC }}'
    fi

# ============================================================================
# Workflows
# ============================================================================

# Full deployment: apply + wait + deploy
full: apply
    @echo "Waiting 30s for LXC to be ready..."
    @sleep 30
    just test::deploy
