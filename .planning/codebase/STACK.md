# Technology Stack

**Analysis Date:** 2026-02-28

## Languages

**Primary:**
- HCL/Terraform 1.8.8 - Infrastructure as Code (OpenTofu)
- Python 3.12 - Configuration management and automation
- YAML 2.0+ - Ansible playbooks and configuration
- Jinja2 - Template rendering for Docker Compose and config files
- Bash - Shell scripts and automation

**Secondary:**
- SQL - PostgreSQL database operations
- TOML - Project and tool configuration

## Runtime

**Environment:**
- Ubuntu 24.04 LTS (LXC container templates)
- Docker Engine + Docker Compose plugin
- Node.js (via Docker images - Twenty CRM containers)

**Package Manager:**
- uv 0.5.20 - Python dependency/virtual environment manager
- pnpm (implicit - used by Twenty CRM docker images)
- Docker image registries: Docker Hub, GHCR (GitHub Container Registry)

**Lockfile:**
- `pyproject.toml` with uv project manager

## Frameworks

**Core:**
- Terraform/OpenTofu 1.8.8 - Infrastructure provisioning
- Ansible 2.17+ - Configuration management and deployment orchestration

**Build/Dev:**
- Just 1.40.0 - Task runner and recipe executor
- pre-commit 4.0.1 - Git hooks for validation
- mise 1.x - Tool version manager (Rust-based asdf replacement)

**Application Frameworks (Docker-based):**
- Twenty CRM v1.17.0 - Open-source CRM application (Node.js-based)

## Key Dependencies

**Critical:**
- ansible 2.17,<2.18 - Configuration management
  - Why it matters: Automates Docker installation, stack deployment, secret injection
- jmespath 1.0.1 - JSON query library for Ansible
- netaddr 1.3.0 - IP address/network manipulation for infrastructure

**Infrastructure:**
- Telmate/proxmox provider - Proxmox VE infrastructure management (LXC provisioning)
- LinuxServer SWAG - nginx reverse proxy with Let's Encrypt SSL + Cloudflare Tunnel support
- twentycrm/twenty - Twenty CRM Docker image (server + worker)
- postgres:16 - PostgreSQL database container
- redis:7-alpine - Redis cache and job queue
- Custom GHCR images (ghcr.io/poindexter12/musa-project-twenty-crm/*):
  - backup - PostgreSQL backup automation
  - rollup - Analytics aggregation cron service
  - webhook-receiver - External webhook handler (Python)

## Configuration

**Environment:**
- 1Password integration for secret management
  - Secrets injected at deployment time via Ansible extra-vars
  - Alternative: 1Password Connect server for CI/CD environments
  - Configuration template: `.mise.local.toml.example`
- Environment variables passed to Docker Compose via `.env` file
  - PostgreSQL credentials
  - Application secret (APP_SECRET)
  - Redis connection string
  - Frontend domain (FRONT_BASE_URL)
  - Storage configuration

**Build:**
- OpenTofu configuration: `terraform/main.tf`, `terraform/variables.tf`, `terraform/outputs.tf`
- Ansible playbooks: `ansible/playbooks/deploy.yaml`
- Role defaults: `ansible/roles/musa/defaults/main.yaml`
- Task configuration: `ansible/roles/musa/tasks/main.yaml`

**Tool Configuration:**
- mise.toml - Tool versions (just, opentofu, uv, pre-commit)
- pyproject.toml - Python dependencies (Ansible, jmespath, netaddr)
- ansible.cfg - Ansible settings (pipelining, SSH multiplexing, YAML output)

## Platform Requirements

**Development:**
- macOS or Linux
- Docker Desktop or Colima (for local Docker environment)
- SSH access to Proxmox infrastructure
- 1Password CLI (`op` command)
- Git (version control)

**Production:**
- Proxmox VE infrastructure (LXC support)
- Joseph node with Ceph storage backend
- Cloudflare account for DNS validation and tunnel
- GHCR access (GitHub private container registry authentication)
- Pi-hole DNS infrastructure (hub-managed)

**Container Platform:**
- Docker-in-LXC (nesting=true required in Proxmox LXC configuration)
- LXC container with nesting enabled (allows Docker daemon inside container)

## Deployment Architecture

**Container Stack (9 services):**

| Service | Image | Purpose | Port |
|---------|-------|---------|------|
| twenty-swag | lscr.io/linuxserver/swag:latest | nginx + Let's Encrypt + cloudflared | 80, 443 |
| server | twentycrm/twenty:v1.17.0 | Twenty CRM main application | 3000 |
| worker | twentycrm/twenty:v1.17.0 | Background job processing | internal |
| db | postgres:16 | PostgreSQL database | 5432 (internal) |
| redis | redis:7-alpine | Cache and job queue | 6379 (internal) |
| twenty-backup | ghcr.io/poindexter12/musa-project-twenty-crm/backup:latest | PostgreSQL automated backups | internal |
| twenty-rollup | ghcr.io/poindexter12/musa-project-twenty-crm/rollup:latest | Analytics aggregation (2 AM daily) | internal |
| twenty-webhook-receiver | ghcr.io/poindexter12/musa-project-twenty-crm/webhook-receiver:latest | External webhook endpoint | 4001 |
| twenty-webhook-worker | ghcr.io/poindexter12/musa-project-twenty-crm/webhook-receiver:latest | Async webhook processing | internal |

**Storage:**
- Ceph storage backend (ceph-seymour) for LXC root filesystem
- Local Docker volumes for: database data, application storage, SWAG config, backups
- Local filesystem backups stored in `/opt/musa/backups/` with 7-day retention

---

*Stack analysis: 2026-02-28*
