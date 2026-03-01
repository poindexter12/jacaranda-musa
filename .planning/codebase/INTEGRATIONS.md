# External Integrations

**Analysis Date:** 2026-02-28

## APIs & External Services

**Cloudflare:**
- Cloudflare Tunnel - External access via `musa-project-test.joeseymour.io`
  - SDK/Client: cloudflared (embedded in SWAG container via linuxserver/mods:universal-cloudflared)
  - Auth: Environment variable `CF_REMOTE_MANAGE_TOKEN` (tunnel JWT)
  - Configuration: `docker-compose.yaml` SWAG service, DOCKER_MODS set to enable cloudflared
  - Public hostname: `musa-project-test.joeseymour.io` → `http://localhost:80`

**Cloudflare DNS-01 Validation (Let's Encrypt):**
- Certbot DNS plugin for Let's Encrypt certificate validation
  - Configuration file: `ansible/roles/musa/templates/cloudflare.ini.j2`
  - Auth: DNS API token (`CF_ZONE_ID`, `CF_ACCOUNT_ID` environment variables in SWAG container)
  - Purpose: Automated SSL certificate generation and renewal via DNS challenge
  - Flow: SWAG container runs certbot with Cloudflare DNS plugin for joeseymour.io subdomain

## Data Storage

**Databases:**
- PostgreSQL 16
  - Connection: Internal Docker network, `db:5432`
  - Client: Native PostgreSQL (twenty-server, worker, and backup containers)
  - Credentials: Username `postgres`, password from `op://Homelab/musa-project-crm-test/pg_password`
  - Database name: `twenty`
  - Environment variables: `PG_DATABASE_URL`, `PG_DATABASE_PASSWORD` in `.env` file
  - Volumes: `db-data` (Docker managed volume for persistence)

**Cache & Job Queue:**
- Redis 7 (Alpine)
  - Connection: Internal Docker network, `redis:6379`
  - Client: Native Redis (twenty-server, worker, webhook-receiver, webhook-worker)
  - Configuration: No authentication required (internal network only)
  - Environment variable: `REDIS_URL=redis://redis:6379`
  - Max memory policy: `noeviction` (configured in docker-compose.yaml)
  - Volumes: No persistent storage (ephemeral)

**File Storage:**
- Local filesystem storage (STORAGE_TYPE=local in `env.j2`)
  - Twenty CRM application storage: Docker volume `server-local-data` → `/app/packages/twenty-server/.local-storage`
  - SWAG nginx config: Docker volume `swag-config` → `/config` (includes Let's Encrypt certs)
  - PostgreSQL backups: Host path `/opt/musa/backups/` (retention: 7 days)

## Authentication & Identity

**Auth Provider:**
- Custom (Twenty CRM internal authentication)
  - Implementation: Twenty CRM application handles user registration and login
  - Application secret: `APP_SECRET` environment variable (from `op://Homelab/musa-project-crm-test/app_secret`)
  - Frontend base URL: `FRONT_BASE_URL=https://musa-project-test.joeseymour.io` (for OAuth/callback redirects)

## Container Registry Authentication

**GHCR (GitHub Container Registry):**
- Private image registry for custom containers
  - Images:
    - `ghcr.io/poindexter12/musa-project-twenty-crm/backup:latest`
    - `ghcr.io/poindexter12/musa-project-twenty-crm/rollup:latest`
    - `ghcr.io/poindexter12/musa-project-twenty-crm/webhook-receiver:latest`
  - Authentication: `docker login ghcr.io` via `ghcr_pat` (GitHub PAT from `op://Homelab/github/pat`)
  - Ansible task: `Log in to GHCR` in `ansible/roles/musa/tasks/main.yaml`
  - Credentials used at deployment time only (not persisted in container)

## Monitoring & Observability

**Error Tracking:**
- Not detected (no external error tracking service configured)

**Logs:**
- Docker local logging driver with log rotation
  - Max size: 10MB per log file
  - Max files: 3 (total ~30MB per service)
  - Compression enabled
  - Ansible logs: `ansible/logs/ansible-YYYYMMDD-HHMMSS.log` (created during each `just test::deploy`)

**Health Checks:**
- Container-level health checks configured for:
  - PostgreSQL: `pg_isready` every 10s (5s timeout, 5 retries, 10s start period)
  - Redis: `redis-cli ping` every 5s (3s timeout, 10 retries, 5s start period)
  - Twenty CRM server: `curl /healthz` every 30s (10s timeout, 3 retries, 60s start period)
  - SWAG: HTTP 200 on port 80 (10s interval, 5s timeout, 5 retries)
  - Webhook receiver: HTTP 200 on `/health` endpoint (30s interval, 5s timeout, 3 retries, 10s start period)

## CI/CD & Deployment

**Hosting:**
- Proxmox VE infrastructure
  - Node: joseph
  - VMID: 1180 (test environment)
  - Container type: LXC
  - Configuration management: Ansible

**CI Pipeline:**
- Not detected (manual deployment via `just test::deploy` recipe)

**Infrastructure as Code:**
- OpenTofu (Terraform-compatible)
  - Manages: LXC container provisioning, SSH certificate signing, inventory generation
  - State: Stored locally (`.terraform/` directory)
  - Modules consumed from lib/ submodule (v1.4.0)

## Environment Configuration

**Required Environment Variables (secrets from 1Password):**
- `cf_tunnel_token` - Cloudflare Tunnel JWT token (op://Homelab/musa-project-crm-test/cf_tunnel_token)
- `cf_api_token` - Cloudflare API token for DNS validation (op://Homelab/musa-project-crm-test/cf_api_token)
- `cf_zone_id` - Cloudflare zone ID for joeseymour.io (op://Homelab/cloudflare/zone_id)
- `cf_account_id` - Cloudflare account ID (op://Homelab/cloudflare/account_id)
- `pg_password` - PostgreSQL password (op://Homelab/musa-project-crm-test/pg_password)
- `app_secret` - Twenty CRM application secret (op://Homelab/musa-project-crm-test/app_secret)
- `ghcr_pat` - GitHub PAT for GHCR authentication (op://Homelab/github/pat)

**Secrets Management:**
- **Primary:** 1Password CLI (`op` command) at deploy time
  - Secrets read via `scripts/op-read` wrapper
  - Injected as Ansible extra-vars: `-e "var=value"`
  - Passed to Jinja2 templates and never written to disk in plaintext (except in running containers)

- **Alternative (CI/CD):** 1Password Connect server
  - Configuration template: `.mise.local.toml.example`
  - Environment variables: `OP_CONNECT_HOST`, `OP_CONNECT_TOKEN`
  - Not currently used (manual deployment workflow)

## Webhooks & Callbacks

**Incoming:**
- Twenty webhook receiver endpoint: `http://localhost:4001` (port 4001 externally via SWAG)
  - Service: `twenty-webhook-receiver` container
  - Health endpoint: `GET /health`
  - Processing flow: Receives webhook → enqueues to Redis → webhook-worker processes asynchronously
  - Circuit breaker: Fail after 5 attempts, reset after 60 seconds (`CIRCUIT_BREAKER_*` env vars)

**Outgoing:**
- Twenty CRM server can trigger webhooks to external systems
  - Configuration: Via Twenty CRM admin interface (not in IaC)
  - Processing: webhook-worker container processes queued jobs from Redis

## Network & DNS

**DNS Resolution:**
- Internal (.lan): Resolved by Pi-hole (hub-managed)
  - Entry: `musa-test.lan` → `192.168.5.180`
  - Exported via Terraform outputs: `dns_entries`, `cname_entries`

- External: Cloudflare managed DNS
  - Public hostname: `musa-project-test.joeseymour.io`
  - CNAME to Cloudflare Tunnel
  - Tunnel directs traffic to SWAG port 80

**Network Access:**
- LXC container internal network: 192.168.5.0/24
- Management IP: 192.168.5.180 (eth0)
- External: Via Cloudflare Tunnel (no direct port forwarding)
- Internal service communication: Docker network (all containers on same compose stack)

## Upstream Dependencies

**Twenty CRM:**
- GitHub: https://github.com/twentyhq/twenty
- Docker image: twentycrm/twenty
- Version pinned: v1.17.0 (default in `ansible/roles/musa/defaults/main.yaml`)
- Container registry: Docker Hub (public)

**SWAG (LinuxServer.io):**
- Documentation: https://docs.linuxserver.io/images/docker-swag
- Docker image: lscr.io/linuxserver/swag:latest
- Features: nginx, Let's Encrypt certbot, Cloudflare DNS plugin
- Cloudflared mod: linuxserver/mods:universal-cloudflared

**Shared Libraries:**
- GitHub: https://github.com/poindexter12/jacaranda-shared-libs (v1.4.0)
- Submodule location: `lib/`
- Consumed modules:
  - `lib/infrastructure/terraform/modules/lxc` - LXC provisioning
  - `lib/infrastructure/terraform/modules/base-infra` - Infrastructure outputs
  - `lib/infrastructure/just/styles.just` - Just recipe formatting utilities
  - `lib/infrastructure/just/secrets.just` - 1Password secret handling
  - `lib/infrastructure/just/terraform.just` - Terraform recipe templates
  - `lib/infrastructure/just/ansible.just` - Ansible recipe templates

---

*Integration audit: 2026-02-28*
