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
# Backup & Restore
# ============================================================================
#
# The backup sidecar writes nightly pg_dump custom-format archives (-Fc, gzip:5)
# into the `musa_backups` docker volume, with 7-day retention. Dumps cover the
# whole `twenty` database: core, metadata, and every workspace_* schema.
#
# Restore is the recovery path for a bad Twenty upgrade. Upgrade migrations are
# one-way — there is no downgrade command — so the only way back is to put an
# older dump under an older image, or to roll the LXC back to a Proxmox
# snapshot. Prefer the snapshot when config or docker state also needs
# rewinding; use `restore` when only Postgres does.
#
# Restoring also reproduces users, workspaces, and the upgrade cursor in
# core.upgradeMigration, which is why it — not a scripted signup — is the way to
# stand up a known-good instance from scratch.

# List Postgres dumps on the LXC, newest first
backups:
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== Musa backups (test) ===%b\n' '{{ BOLD }}' '{{ NC }}'
    ssh -o BatchMode=yes root@{{ musa_host }} bash -s <<'REMOTE'
    set -euo pipefail
    dir=$(docker volume inspect musa_backups | sed -n 's/.*"Mountpoint": "\([^"]*\)".*/\1/p')
    [ -n "$dir" ] || { echo "could not resolve the musa_backups volume"; exit 1; }
    ls -lht "$dir" | tail -n +2
    REMOTE

# Take an on-demand Postgres dump — run this before any upgrade
backup-now:
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b-> Taking on-demand Musa dump%b\n' '{{ CYAN }}' '{{ NC }}'
    ssh -o BatchMode=yes root@{{ musa_host }} "docker exec twenty-backup /backup.sh"
    printf '%b Dump complete%b\n' '{{ GREEN }}' '{{ NC }}'

# Stops every service holding a Postgres connection, drops and recreates the
# `twenty` database, restores the archive, flushes Redis so cached metadata
# cannot outlive the data it describes, then brings the stack back up.
#
#   just test::restore                              # newest dump
#   just test::restore twenty_20260816_010000.dump  # a specific one
#
# Restore Postgres from a dump (default: newest). DESTRUCTIVE — drops the database.
[confirm("Restore the Musa test database from a dump? This DROPS the current database!")]
restore file="latest":
    #!/usr/bin/env bash
    set -euo pipefail
    printf '%b=== Restoring Musa database (test) ===%b\n' '{{ BOLD }}' '{{ NC }}'
    ssh -o BatchMode=yes root@{{ musa_host }} bash -s -- '{{ file }}' <<'REMOTE'
    set -euo pipefail
    DUMP="$1"

    DIR=$(docker volume inspect musa_backups | sed -n 's/.*"Mountpoint": "\([^"]*\)".*/\1/p')
    [ -n "$DIR" ] || { echo "could not resolve the musa_backups volume"; exit 1; }

    if [ "$DUMP" = "latest" ]; then
        DUMP=$(ls -t "$DIR"/*.dump 2>/dev/null | head -1 | xargs -r basename)
    fi
    [ -n "$DUMP" ]        || { echo "no dumps found in $DIR"; exit 1; }
    [ -f "$DIR/$DUMP" ]   || { echo "no such dump: $DUMP"; exit 1; }

    echo "-> Restoring from $DUMP ($(du -h "$DIR/$DUMP" | cut -f1))"

    # Verify the archive before touching the live database, so a corrupt dump
    # fails here rather than halfway through a drop/recreate.
    docker run --rm -v musa_backups:/backups postgres:16 \
        pg_restore --list "/backups/$DUMP" >/dev/null
    echo "   archive integrity OK"

    set -a; . /opt/musa/.env; set +a
    : "${PG_DATABASE_PASSWORD:?PG_DATABASE_PASSWORD missing from /opt/musa/.env}"

    cd /opt/musa

    echo "-> Stopping database consumers"
    docker compose stop server worker backup rollup webhook-receiver webhook-worker

    echo "-> Dropping and recreating the database"
    docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
        -c "select pg_terminate_backend(pid) from pg_stat_activity
            where datname = 'twenty' and pid <> pg_backend_pid();" >/dev/null
    docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
        -c 'drop database if exists twenty;'
    docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
        -c 'create database twenty;'

    echo "-> Restoring dump"
    docker run --rm --network musa_default -v musa_backups:/backups \
        -e PGPASSWORD="$PG_DATABASE_PASSWORD" postgres:16 \
        pg_restore -h db -U postgres -d twenty --no-owner --no-privileges \
        "/backups/$DUMP"

    # Redis carries Twenty's workspace metadata cache and job queues. Left
    # alone it would describe the database we just replaced.
    echo "-> Flushing Redis"
    docker compose exec -T redis redis-cli FLUSHALL >/dev/null

    echo "-> Starting services"
    docker compose up -d
    REMOTE
    printf '%b Restore complete — run just test::validate to check health%b\n' '{{ GREEN }}' '{{ NC }}'

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
        -e "pg_password=$(secret-read 'op://Homelab/musa-project-crm-test/pg_password')" \
        -e "app_secret=$(secret-read 'op://Homelab/musa-project-crm-test/app_secret')" \
        -e "encryption_key=$(secret-read 'op://Homelab/musa-project-crm-test/encryption_key')" \
        -e "twenty_api_key=$(secret-read 'op://Homelab/musa-project-crm-test/twenty_api_key')" \
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
