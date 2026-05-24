# Musa Project — Test Environment (single LXC, Proxmox HA-managed)
#
# 1 LXC on joseph (initial placement), failover to any cluster node via Proxmox HA:
#   test.app.musa: VMID 1095, 192.168.5.95
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

# Fully-qualified hostname for SSH / health checks. Resolves via Pi-hole's
# mgmt.home.arpa zone (registry-published) — required so SSH host certs and
# known_hosts entries match. Change here if the LXC is renamed.
musa_host := "test.app.musa.mgmt.home.arpa"

# Show available recipes for this module
@_default:
    just --list test

# ============================================================================
# Terraform Operations
# ============================================================================

# Provider credentials injected via TF_VAR (Terraform reads TF_VAR_* automatically).
# Proxmox endpoint + token secret are shared across the homelab — same values as
# jacaranda-foundation services. infra.yaml carries the non-secret token id.
export TF_VAR_ssh_public_key := `op-read 'op://Homelab/musa-project-test/public key'`
export TF_VAR_proxmox_endpoint := "https://192.168.5.5:8006/api2/json"
export TF_VAR_proxmox_api_token_secret := `op-read 'op://Homelab/Jacaranda Proxmox Deploy/api token'`

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
    ssh -o BatchMode=yes -o ConnectTimeout=5 root@{{ musa_host }} "cd /opt/musa && \
        cp -f docker-compose.yaml docker-compose.yaml.bak 2>/dev/null && \
        cp -f .env .env.bak 2>/dev/null" 2>/dev/null || true

# Rollback to previous deployment
[confirm("Roll back Musa test to previous deployment?")]
rollback:
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== Rolling back Musa (test) ===%b\n' '{{ BOLD }}' '{{ NC }}'

    if ! ssh -o BatchMode=yes root@{{ musa_host }} "test -f /opt/musa/docker-compose.yaml.bak" 2>/dev/null; then
        printf '%b  SKIP: No rollback snapshot on {{ musa_host }}%b\n' '{{ YELLOW }}' '{{ NC }}'
        exit 0
    fi

    ssh -o BatchMode=yes root@{{ musa_host }} "cd /opt/musa && \
        cp -f docker-compose.yaml.bak docker-compose.yaml && \
        cp -f .env.bak .env"
    printf '%b  Restored config from snapshot%b\n' '{{ GREEN }}' '{{ NC }}'

    ssh -o BatchMode=yes root@{{ musa_host }} "cd /opt/musa && docker compose up -d --force-recreate" 2>/dev/null || true

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
        -e "encryption_key=$(secret-read 'op://Homelab/musa-project-crm-test/encryption_key')" \
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
    printf '{{ musa_host }}: '
    dig +short {{ musa_host }} || echo "FAIL"

    echo "--- SSH ---"
    printf '{{ musa_host }}: '
    ssh -o ConnectTimeout=5 -o BatchMode=yes root@{{ musa_host }} hostname 2>/dev/null || echo "FAIL"

# Validate deployment health
validate: verify
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== Validate test (Musa) ===%b\n' '{{ BOLD }}' '{{ NC }}'
    printf '%b--- {{ musa_host }} ---%b\n' '{{ BOLD }}' '{{ NC }}'

    # Docker daemon
    printf '  Docker: '
    if ssh -o BatchMode=yes root@{{ musa_host }} "docker info" >/dev/null 2>&1; then
        printf '%b OK%b\n' '{{ GREEN }}' '{{ NC }}'
    else
        printf '%b FAIL%b\n' '{{ RED }}' '{{ NC }}'
    fi

    # Docker Compose plugin
    printf '  Compose: '
    if ssh -o BatchMode=yes root@{{ musa_host }} "docker compose version" >/dev/null 2>&1; then
        printf '%b OK%b\n' '{{ GREEN }}' '{{ NC }}'
    else
        printf '%b FAIL%b\n' '{{ RED }}' '{{ NC }}'
    fi

    # Docker containers (show whatever is running)
    running=$(ssh -o BatchMode=yes root@{{ musa_host }} "docker ps --format '{{ '{{' }}.Names{{ '}}' }}'" 2>/dev/null || true)
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
    printf '%b=== {{ musa_host }} ===%b\n' '{{ BOLD }}' '{{ NC }}'
    containers=$(ssh -o BatchMode=yes root@{{ musa_host }} "docker ps --format '{{ '{{' }}.Names{{ '}}' }}'" 2>/dev/null || true)
    if [ -n "$containers" ]; then
        echo "$containers" | while read -r container; do
            printf '%b--- %s ---%b\n' '{{ CYAN }}' "$container" '{{ NC }}'
            ssh -o BatchMode=yes root@{{ musa_host }} "docker logs $container --tail=5" 2>/dev/null || echo "  not reachable"
        done
    else
        printf '  %b(no containers running)%b\n' '{{ YELLOW }}' '{{ NC }}'
    fi

# ============================================================================
# Workflows
# ============================================================================

# Poll until the LXC accepts SSH (max ~3 min). Replaces a fixed sleep so
# `full` doesn't wait longer than necessary, and fails loudly if the LXC
# never comes up. Strips stale known_hosts entries first because the LXC
# host key changes whenever terraform destroys + recreates the container.
# UserKnownHostsFile=/dev/null on the probe itself keeps it tolerant of
# any further host-key churn during the poll loop.
[private]
wait-ssh:
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b-> Clearing stale known_hosts entries for {{ musa_host }}%b\n' '{{ CYAN }}' '{{ NC }}'
    ssh-keygen -R {{ musa_host }} >/dev/null 2>&1 || true
    printf '%b-> Waiting for SSH on {{ musa_host }}%b\n' '{{ CYAN }}' '{{ NC }}'
    for i in $(seq 1 36); do
        if ssh -o BatchMode=yes -o ConnectTimeout=5 \
               -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null \
               root@{{ musa_host }} true 2>/dev/null; then
            printf '%b   SSH ready (after %ds)%b\n' '{{ GREEN }}' "$((i * 5))" '{{ NC }}'
            exit 0
        fi
        sleep 5
    done
    printf '%b   SSH never responded after 3 min on {{ musa_host }}%b\n' '{{ RED }}' '{{ NC }}'
    exit 1

# Full deployment: apply + wait-for-SSH + deploy
full: apply wait-ssh deploy
