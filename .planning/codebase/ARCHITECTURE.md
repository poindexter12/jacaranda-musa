# Architecture

**Analysis Date:** 2026-02-28

## Pattern Overview

**Overall:** Infrastructure-as-Code layered architecture with clear separation between infrastructure provisioning (Terraform), configuration management (Ansible), and application services (Docker Compose).

**Key Characteristics:**
- Single-node LXC container with Docker-in-LXC nesting for multi-service deployment
- Infrastructure defined in code via OpenTofu/Terraform modules from shared library
- Declarative service configuration via Ansible roles consuming templated configurations
- Nine-container Docker Compose stack deployed inside the LXC
- Externally accessible via Cloudflare Tunnel embedded in SWAG reverse proxy container
- Secrets injected at deployment time via 1Password integration through justfile recipes

## Layers

**Infrastructure Layer (Terraform):**
- Purpose: Provision and manage the LXC container on Proxmox
- Location: `terraform/`, `terraform/envs/test/`, `terraform/envs/prod/`
- Contains: OpenTofu/Terraform configuration files that create/destroy LXC instances
- Depends on: Proxmox API, base-infra module for shared infrastructure values (VLAN config, SSH keys, storage)
- Used by: Ansible (receives generated inventory); operations (apply/destroy)
- Module source: `lib/infrastructure/terraform/modules/lxc` (shared, v1.4.0)
- Key outputs: Ansible inventory file, DNS entries, CNAME entries, management IPs

**Configuration Management Layer (Ansible):**
- Purpose: Install Docker, configure services, deploy application stack
- Location: `ansible/playbooks/`, `ansible/roles/musa/`
- Contains: Playbooks that orchestrate role execution; musa role with tasks, handlers, templates
- Depends on: LXC container created by Terraform, 1Password secrets injected via justfile
- Used by: Justfile deploy recipe; operations for idempotent redeployment
- Pattern: Single role (musa) applied to all musa-group hosts; handlers trigger stack restart on config change

**Application Layer (Docker Compose):**
- Purpose: Run Nine integrated services (CRM, database, cache, webhooks, reverse proxy)
- Location: `/opt/musa/docker-compose.yaml` (deployed by Ansible to LXC)
- Contains: Service definitions for Twenty CRM, PostgreSQL, Redis, SWAG, backup, rollup, webhook services
- Depends on: Docker Engine installed by Ansible, Cloudflare Tunnel token, secrets in .env
- Used by: Docker daemon inside LXC; accessed externally via Cloudflare Tunnel

**Orchestration Layer (justfile):**
- Purpose: Provide consistent command interface for infrastructure and application lifecycle
- Location: `justfile`, `test.just`, `prod.just`
- Contains: Recipes that invoke terraform/ansible with appropriate options and secret injection
- Depends on: OpenTofu, Ansible, 1Password CLI, shared justfile utilities from lib
- Used by: Human operators; CI/CD pipelines

## Data Flow

**Deployment Flow (Infrastructure → Services):**

1. Operator runs `just test::full`
2. Justfile recipe invokes `terraform apply` in `terraform/envs/test/`
3. Terraform calls LXC module from `lib/infrastructure/terraform/modules/lxc`
4. LXC module provisions container on Proxmox node (joseph), generates Ansible inventory → `ansible/inventory/test.yaml`
5. Justfile waits 30 seconds for LXC boot
6. Justfile recipe invokes Ansible playbook with 1Password secrets injected as extra-vars
7. Ansible musa role executes tasks in order:
   - Install Docker + Docker Compose
   - Authenticate to GHCR (private image registry)
   - Create `/opt/musa/` directories
   - Template configuration files (cloudflare.ini, docker-compose.yaml, .env, nginx config)
   - Start Docker Compose stack
   - Wait for health checks (SWAG port 80, Twenty /healthz)
8. All nine containers running; Cloudflare Tunnel active; Twenty CRM accessible at musa-project-test.joeseymour.io

**Request Flow (External → Twenty CRM):**

```
Internet
   ↓
Cloudflare Edge (DNS: musa-project-test.joeseymour.io)
   ↓
Cloudflare Tunnel (public hostname → localhost:80)
   ↓
musa-test.lan (192.168.5.180, LXC)
   ↓
Docker network (bridge)
   ↓
SWAG container (twenty-swag, port 80/443)
   ├─ cloudflared daemon (embedded, Tunnel token)
   ├─ Nginx (reverse proxy)
   └─ Certbot (DNS-01 validation via Cloudflare API)
   ↓
twenty.conf nginx proxy rules
   ↓
server container (port 3000, Twenty CRM main app)
   ↓
PostgreSQL (db container, port 5432, internal only)
Redis (redis container, port 6379, internal only)
```

**Configuration State Flow:**

Secrets → 1Password items → justfile op-read script → Ansible extra-vars → Jinja2 templates → Config files on LXC

Example: `cf_tunnel_token` (Cloudflare Tunnel JWT)
- Stored in: `op://Homelab/musa-project-crm-test/cf_tunnel_token`
- Read by: `just test::deploy` (via `op-read` script in `scripts/op-read`)
- Passed as: `-e "cf_tunnel_token=$(op read ...)"`
- Used in: `cloudflare.ini.j2` template → rendered as `CF_REMOTE_MANAGE_TOKEN` env var
- Consumed by: SWAG container's cloudflared process for Tunnel authentication

**State Management:**

- Infrastructure state: `terraform/envs/test/terraform.tfstate` (local; encryption keys in `.env.local` injected via `op-connect.sh`)
- Service state: Docker Compose volumes (db-data, server-local-data, backups, swag-config) persist on LXC
- Configuration: Git-tracked templates; applied via Ansible; idempotent re-runs safe
- Secrets: Never committed; sourced from 1Password at deploy time only

## Key Abstractions

**LXC Module:**
- Purpose: Abstract Proxmox LXC container creation, SSH CA integration, inventory generation
- Examples: `lib/infrastructure/terraform/modules/lxc/main.tf`, `lib/infrastructure/terraform/modules/lxc/outputs.tf`
- Pattern: Reusable module consumed by `terraform/main.tf` with environment-specific instances in `terraform/envs/{test,prod}/main.tf`
- Handles: Container lifecycle, NIC setup, SSH host certificate signing, Ansible inventory generation

**Base Infrastructure Module:**
- Purpose: Abstract shared infrastructure values (Proxmox API, VLANs, SSH keys, storage, DNS)
- Examples: `lib/infrastructure/terraform/modules/base-infra/` (sourced as `module.base_infra` in test/prod envs)
- Pattern: Single source of truth for infrastructure variables; consumed by all services
- Provides: `proxmox_api_url`, `vlans`, `ssh_public_key`, `ssh_user_ca_pubkey`, `dns_server`, `storage`, `lxc_template_storage`

**Musa Role:**
- Purpose: Encapsulate all Musa-specific configuration (Docker, services, templates)
- Examples: `ansible/roles/musa/tasks/main.yaml`, `ansible/roles/musa/templates/`
- Pattern: Idempotent role tasks; templates injected via Jinja2; handlers trigger service restart on config change
- Single role applied to all musa-group hosts; no per-host variations

**Docker Compose Service Definitions:**
- Purpose: Declaratively define nine interdependent services with health checks, volumes, logging
- Examples: `server`, `worker`, `db`, `redis`, `swag`, `backup`, `rollup`, `webhook-receiver`, `webhook-worker`
- Pattern: Templated compose file (`docker-compose.yaml.j2`) → rendered with environment variables
- Health checks: All services include `healthcheck` directives; startup order defined via `depends_on: condition: service_healthy`

## Entry Points

**CLI Entry Points (justfile):**
- Location: `justfile`, `test.just`
- `just test::full` - Primary deployment: terraform apply + ansible deploy
- `just test::deploy` - Redeploy without terraform (idempotent)
- `just test::validate` - Health check services
- `just upgrade` - Update OpenTofu providers
- `just check-secrets` - Verify 1Password items exist

**Terraform Entry Points:**
- `terraform/envs/test/main.tf` - Test environment (single node, VMID 1180, joseph)
- `terraform/envs/prod/main.tf` - Production environment (placeholder with base-infra module)

**Ansible Entry Points:**
- `ansible/playbooks/deploy.yaml` - Deploy playbook; targets `musa` group; applies musa role
- `ansible/roles/musa/tasks/main.yaml` - Task execution: Docker install → config templates → service startup → health verify

**Container Entry Points (Docker Compose):**
- `swag` - SWAG reverse proxy + Cloudflare Tunnel; listens on 80/443; cloudflared daemon active
- `server` - Twenty CRM main application; port 3000; health endpoint `/healthz`
- `worker` - Background job processor; no external port; depends on db + redis + server
- `db` - PostgreSQL database; port 5432 (internal only)
- `redis` - Cache and job queue; port 6379 (internal only)
- `backup` - PostgreSQL backup cron; volumes `/backups`; runs daily retention
- `rollup` - Analytics rollup cron; runs 2 AM daily
- `webhook-receiver` - External webhook listener; port 4001 (maps to 5000 inside)
- `webhook-worker` - Async webhook processor; depends on redis + server

## Error Handling

**Strategy:** Health checks at multiple levels; graceful degradation; logged output to stdout/stderr captured by Docker logging drivers.

**Patterns:**

Health Check Chains:
- Terraform: Pre-flight checks via `check "vmid_allocation"` block validates VMID allocation
- Ansible: `ansible.builtin.assert` validates required variables before execution; URI/command tasks use `until: ... retries: 30 delay: 5` for polling
- Docker Compose: Service healthchecks define test command, interval, timeout, retries, start_period; startup order enforced via `depends_on: condition: service_healthy`

Error Recovery:
- Terraform apply: Idempotent; can re-run safely if transient failures occur
- Ansible tasks: Use `creates:` directive to skip already-completed steps; handlers for conditional restart
- Docker Compose: `restart: unless-stopped` policy; services restart automatically on crash
- Ansible verification: Retries with delays (30 attempts, 5s per attempt = 150s timeout) for SWAG; 30 attempts, 10s per attempt for Twenty healthz

Logging:
- Terraform: Output to stdout/stderr; apply logs captured in `ansible/logs/` via justfile
- Ansible: `ANSIBLE_LOG_PATH` set to timestamped file in `ansible/logs/`; YAML output formatting via `ansible.cfg`
- Docker: Local logging driver with rotation (max-size 10m, max-file 3, compress enabled)

## Cross-Cutting Concerns

**Logging:** Docker local logging driver configured in compose file; rotate at 10MB; compress old files; Ansible logs to timestamped files in `ansible/logs/`; Terraform output to stderr/stdout.

**Validation:** Terraform checks VMID allocation; Ansible asserts required variables; Docker health checks on all services; justfile recipes poll for DNS/SSH/container readiness before declaring success.

**Authentication:** SSH via LXC module's SSH CA integration (host certificates); Ansible uses SSH keys from `ssh_public_key` variable; Cloudflare Tunnel authenticated via `CF_REMOTE_MANAGE_TOKEN` env var; GHCR login via Docker login in Ansible task.

**Secrets Management:** 1Password as source of truth; secrets never committed; injected at deploy time via justfile op-read script; passed as Ansible extra-vars; templated into .env and config files; marked `no_log: true` in Ansible tasks.

**Idempotency:** All Ansible tasks designed to be rerun safely (uses `creates:` directives, `changed_when: false` for read-only operations, handlers for conditional restarts); Docker Compose is naturally idempotent; Terraform apply can be re-run after failures.

---

*Architecture analysis: 2026-02-28*
