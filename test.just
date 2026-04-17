# Musa Project — Test Environment
#
# Single-node LXC on joseph: VMID 1180, 192.168.5.180
#
# Usage: just test::<recipe>
#
# Examples:
#   just test::apply         # Create test LXC
#   just test::deploy        # Deploy Twenty CRM stack
#   just test::full          # Apply + wait + deploy
#   just test::validate      # Check service health

import 'lib/infrastructure/just/terraform.just'
import 'lib/infrastructure/just/ansible.just'

# ============================================================================
# Terraform Operations
# ============================================================================

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
    host="musa-test"
    printf '%b-> Saving rollback snapshot%b\n' '{{ CYAN }}' '{{ NC }}'
    ssh -o BatchMode=yes root@$host.lan "cd /opt/musa && \
        cp -f docker-compose.yaml docker-compose.yaml.bak 2>/dev/null && \
        cp -f .env .env.bak 2>/dev/null" || true

# Rollback to previous deployment
[confirm("Roll back Musa test to previous deployment?")]
rollback:
    #!/usr/bin/env bash
    set -euo pipefail
    host="musa-test"

    printf '%b=== Rolling back Musa (test) ===%b\n' '{{ BOLD }}' '{{ NC }}'

    # Check backup files exist
    if ! ssh -o BatchMode=yes root@$host.lan "test -f /opt/musa/docker-compose.yaml.bak"; then
        printf '%b  FAIL: No rollback snapshot found. Run a deploy first.%b\n' '{{ RED }}' '{{ NC }}'
        exit 1
    fi

    # Restore backup files
    ssh -o BatchMode=yes root@$host.lan "cd /opt/musa && \
        cp -f docker-compose.yaml.bak docker-compose.yaml && \
        cp -f .env.bak .env"
    printf '%b  Restored config from snapshot%b\n' '{{ GREEN }}' '{{ NC }}'

    # Recreate containers
    ssh -o BatchMode=yes root@$host.lan "cd /opt/musa && docker compose up -d --force-recreate"
    printf '%b  Waiting 30s for services to start...%b\n' '{{ CYAN }}' '{{ NC }}'
    sleep 30

    # Quick health check
    if ssh -o BatchMode=yes root@$host.lan "curl -sf http://localhost:3000/healthz" >/dev/null 2>&1; then
        printf '%b  Rollback OK — Twenty CRM healthy%b\n' '{{ GREEN }}' '{{ NC }}'
    else
        printf '%b  WARNING: Twenty CRM health check failed after rollback%b\n' '{{ RED }}' '{{ NC }}'
        exit 1
    fi

# ============================================================================
# Ansible Operations
# ============================================================================

# Deploy Musa services to test node
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

    host="musa-test"

    echo "--- DNS ---"
    printf '%s.lan: ' "$host"
    dig +short $host.lan || echo "FAIL"

    echo "--- SSH ---"
    printf '%s.lan: ' "$host"
    ssh -o ConnectTimeout=5 -o BatchMode=yes root@$host.lan hostname 2>/dev/null || echo "FAIL"

# Validate deployment health
validate: verify
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== Validate test (Musa / Twenty CRM) ===%b\n' '{{ BOLD }}' '{{ NC }}'

    host="musa-test"

    printf '%b--- %s.lan ---%b\n' '{{ BOLD }}' "$host" '{{ NC }}'

    # Docker containers
    for container in twenty-swag server worker db redis twenty-backup twenty-rollup twenty-webhook-receiver twenty-webhook-worker; do
        if ssh -o BatchMode=yes root@$host.lan "docker ps --format '{{ '{{' }}.Names{{ '}}' }}'" 2>/dev/null | grep -q "$container"; then
            printf '%b  OK %s running%b\n' '{{ GREEN }}' "$container" '{{ NC }}'
        else
            printf '%b  FAIL %s not running%b\n' '{{ RED }}' "$container" '{{ NC }}'
        fi
    done

    echo ""
    echo "--- Health Check ---"
    printf 'Twenty CRM healthz: '
    if ssh -o BatchMode=yes root@$host.lan "curl -sf http://localhost:3000/healthz" 2>/dev/null; then
        printf ' %b OK%b\n' '{{ GREEN }}' '{{ NC }}'
    else
        printf ' %b FAIL%b\n' '{{ RED }}' '{{ NC }}'
    fi

    printf 'SWAG (port 80): '
    if ssh -o BatchMode=yes root@$host.lan "curl -sf -o /dev/null -w 'HTTP %{http_code}' http://localhost:80" 2>/dev/null; then
        printf ' %b OK%b\n' '{{ GREEN }}' '{{ NC }}'
    else
        printf ' %b FAIL%b\n' '{{ RED }}' '{{ NC }}'
    fi

    echo ""
    echo "--- External Access ---"
    printf 'External (Cloudflare Tunnel): '
    if curl -sf -o /dev/null -w 'HTTP %{http_code}' --max-time 10 https://musa-project-test.joeseymour.io 2>/dev/null; then
        printf ' %b OK%b\n' '{{ GREEN }}' '{{ NC }}'
    else
        printf ' %b FAIL%b\n' '{{ RED }}' '{{ NC }}'
    fi || true

# ============================================================================
# Logs
# ============================================================================

# View container logs
logs:
    #!/usr/bin/env bash
    set -euo pipefail
    host="musa-test"
    printf '%b=== %s.lan ===%b\n' '{{ BOLD }}' "$host" '{{ NC }}'
    for container in twenty-swag server worker db redis twenty-backup twenty-rollup twenty-webhook-receiver; do
        printf '%b--- %s ---%b\n' '{{ CYAN }}' "$container" '{{ NC }}'
        ssh -o BatchMode=yes root@$host.lan "docker logs $container --tail=5" 2>/dev/null || echo "  not reachable"
    done

# ============================================================================
# Workflows
# ============================================================================

# Full deployment: apply + wait + deploy
full: apply
    @echo "Waiting 30s for LXC to be ready..."
    @sleep 30
    just test::deploy
