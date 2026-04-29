# Musa Project — Test Environment (3-Node HA Cluster)
#
# 3 LXCs across joseph, everette, maxwell:
#   test.app1.app.musa: VMID 1190, 192.168.5.190 (joseph)
#   test.app2.app.musa: VMID 1191, 192.168.5.191 (everette)
#   test.bak.backup.musa:  VMID 1192, 192.168.5.192 (maxwell)
#
# Usage: just test::<recipe>
#
# Examples:
#   just test::apply         # Create 3 test LXCs
#   just test::deploy        # Deploy to all nodes
#   just test::full          # Apply + wait + deploy
#   just test::validate      # Check all nodes health

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
    hosts=("test.app1.app.musa" "test.app2.app.musa" "test.bak.backup.musa")
    printf '%b-> Saving rollback snapshot%b\n' '{{ CYAN }}' '{{ NC }}'
    for host in "${hosts[@]}"; do
        ssh -o BatchMode=yes -o ConnectTimeout=5 root@$host.lan "cd /opt/musa && \
            cp -f docker-compose.yaml docker-compose.yaml.bak 2>/dev/null && \
            cp -f .env .env.bak 2>/dev/null" 2>/dev/null || true
    done

# Rollback to previous deployment
[confirm("Roll back Musa test to previous deployment?")]
rollback:
    #!/usr/bin/env bash
    set -euo pipefail
    hosts=("test.app1.app.musa" "test.app2.app.musa" "test.bak.backup.musa")

    printf '%b=== Rolling back Musa (test) ===%b\n' '{{ BOLD }}' '{{ NC }}'

    for host in "${hosts[@]}"; do
        printf '%b--- %s ---%b\n' '{{ CYAN }}' "$host" '{{ NC }}'

        # Check backup files exist
        if ! ssh -o BatchMode=yes root@$host.lan "test -f /opt/musa/docker-compose.yaml.bak" 2>/dev/null; then
            printf '%b  SKIP: No rollback snapshot on %s%b\n' '{{ YELLOW }}' "$host" '{{ NC }}'
            continue
        fi

        # Restore backup files
        ssh -o BatchMode=yes root@$host.lan "cd /opt/musa && \
            cp -f docker-compose.yaml.bak docker-compose.yaml && \
            cp -f .env.bak .env"
        printf '%b  Restored config from snapshot%b\n' '{{ GREEN }}' '{{ NC }}'

        # Recreate containers
        ssh -o BatchMode=yes root@$host.lan "cd /opt/musa && docker compose up -d --force-recreate" 2>/dev/null || true
    done

    printf '%b  Waiting 30s for services to start...%b\n' '{{ CYAN }}' '{{ NC }}'
    sleep 30
    printf '%b  Rollback complete — run just test::validate to check health%b\n' '{{ GREEN }}' '{{ NC }}'

# ============================================================================
# Ansible Operations
# ============================================================================

# Deploy Musa services to all test nodes
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

    hosts=("test.app1.app.musa" "test.app2.app.musa" "test.bak.backup.musa")

    echo "--- DNS ---"
    for host in "${hosts[@]}"; do
        printf '%s.lan: ' "$host"
        dig +short $host.lan || echo "FAIL"
    done

    echo "--- SSH ---"
    for host in "${hosts[@]}"; do
        printf '%s.lan: ' "$host"
        ssh -o ConnectTimeout=5 -o BatchMode=yes root@$host.lan hostname 2>/dev/null || echo "FAIL"
    done

# Validate deployment health
validate: verify
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== Validate test (Musa / 3-Node HA Cluster) ===%b\n' '{{ BOLD }}' '{{ NC }}'

    hosts=("test.app1.app.musa" "test.app2.app.musa" "test.bak.backup.musa")

    for host in "${hosts[@]}"; do
        printf '%b--- %s.lan ---%b\n' '{{ BOLD }}' "$host" '{{ NC }}'

        # Docker daemon
        printf '  Docker: '
        if ssh -o BatchMode=yes root@$host.lan "docker info" >/dev/null 2>&1; then
            printf '%b OK%b\n' '{{ GREEN }}' '{{ NC }}'
        else
            printf '%b FAIL%b\n' '{{ RED }}' '{{ NC }}'
        fi

        # Docker Compose plugin
        printf '  Compose: '
        if ssh -o BatchMode=yes root@$host.lan "docker compose version" >/dev/null 2>&1; then
            printf '%b OK%b\n' '{{ GREEN }}' '{{ NC }}'
        else
            printf '%b FAIL%b\n' '{{ RED }}' '{{ NC }}'
        fi

        # Docker containers (show whatever is running)
        running=$(ssh -o BatchMode=yes root@$host.lan "docker ps --format '{{ '{{' }}.Names{{ '}}' }}'" 2>/dev/null || true)
        if [ -n "$running" ]; then
            echo "  Containers:"
            echo "$running" | while read -r c; do
                printf '%b    OK %s running%b\n' '{{ GREEN }}' "$c" '{{ NC }}'
            done
        else
            printf '  Containers: %b(none running — expected before HA deployment)%b\n' '{{ YELLOW }}' '{{ NC }}'
        fi

        echo ""
    done

# ============================================================================
# Logs
# ============================================================================

# View container logs
logs:
    #!/usr/bin/env bash
    set -euo pipefail
    hosts=("test.app1.app.musa" "test.app2.app.musa" "test.bak.backup.musa")
    for host in "${hosts[@]}"; do
        printf '%b=== %s.lan ===%b\n' '{{ BOLD }}' "$host" '{{ NC }}'
        containers=$(ssh -o BatchMode=yes root@$host.lan "docker ps --format '{{ '{{' }}.Names{{ '}}' }}'" 2>/dev/null || true)
        if [ -n "$containers" ]; then
            echo "$containers" | while read -r container; do
                printf '%b--- %s ---%b\n' '{{ CYAN }}' "$container" '{{ NC }}'
                ssh -o BatchMode=yes root@$host.lan "docker logs $container --tail=5" 2>/dev/null || echo "  not reachable"
            done
        else
            printf '  %b(no containers running)%b\n' '{{ YELLOW }}' '{{ NC }}'
        fi
    done

# ============================================================================
# Workflows
# ============================================================================

# Full deployment: apply + wait + deploy
full: apply
    @echo "Waiting 30s for LXC to be ready..."
    @sleep 30
    just test::deploy
