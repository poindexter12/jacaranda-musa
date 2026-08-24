# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Musa Project — Twenty CRM Service

## Quick Reference

**Purpose:** Twenty CRM at musa-project-crm-test.joeseymour.io behind Caddy + Cloudflare Tunnel on a single LXC
**Repository:** https://github.com/poindexter12/jacaranda-musa
**Shared Libraries:** `lib/` submodule (jacaranda-shared-libs v1.5.0)
**Secrets:** 1Password `op://Homelab/musa-project-crm-test/*` + shared Cloudflare/GitHub items
**Logs:** `ansible/logs/` (verbose Ansible output)
**Tool versions:** `mise.toml` (canonical source — just, opentofu, uv, pre-commit)

**First-time setup:**

```bash
git submodule update --init  # Initialize shared-libs
mise trust && mise install   # Install toolchain
uv sync                      # Create Python venv for Ansible
```

**Quick Commands:**

```bash
just --list                # Show all recipes
just check-secrets         # Verify 1Password items exist
just test::full            # Create LXC + deploy
just test::validate        # Check service health
just test::logs            # View container logs
just upgrade               # Upgrade OpenTofu providers
```

## Architecture

**Docker-in-LXC Design:**

Musa runs as a single LXC container with Docker nesting enabled (`nesting=true` in Proxmox). This allows running the full Twenty CRM stack (9 containers) inside the LXC without VM overhead.

**Traffic Flow (External via Cloudflare Tunnel):**

```text
Internet -> Cloudflare Edge -> Tunnel
                                 |
                                 v
                           twenty-cloudflared (own container)
                                 |
                                 v
                           twenty-caddy :80 (HTTP-only)
                                 |
                                 v
                           Caddyfile → server:3000
                                 |
                                 v
                           Twenty CRM server
                                 |
                      +----------+----------+
                      v                     v
                PostgreSQL :5432       Redis :6379
```

**Stack Components:**

| Container | Purpose | Port |
| --------- | ------- | ---- |
| twenty-caddy | Caddy reverse proxy (HTTP-only, no certificates) | 80 |
| twenty-cloudflared | Cloudflare Tunnel (only path in) | — |
| server | Twenty CRM main application | 3000 |
| worker | Background job processing | — |
| db | PostgreSQL database | 5432 |
| redis | Cache and job queue | 6379 |
| twenty-backup | PostgreSQL backups to `/backups` | — |
| twenty-rollup | Analytics aggregation cron (2 AM daily) | — |
| twenty-webhook-receiver | External webhook endpoint | 4001 |
| twenty-webhook-worker | Async webhook processing | — |

**Key Features:**

- **Caddy:** The only reverse proxy — deliberately HTTP-only, since cloudflared is the sole path in and TLS terminates at Cloudflare's edge. No certificates anywhere in the stack.
- **Cloudflare Tunnel:** Standalone cloudflared container (credential file lives on the host at /opt/musa/cloudflared/credentials.json — verified by Ansible, never templated)
- **Twenty CRM:** Modern open-source CRM (https://github.com/twentyhq/twenty)
- **Backups:** Automated PostgreSQL backups via custom container
- **Webhooks:** Dedicated receiver and worker for external integrations

## Ingress Migration (2026-08-18: SWAG → Caddy + cloudflared)

SWAG was retired because its cloudflared DOCKER_MOD coupled the tunnel to
certbot: every restart ran a Let's Encrypt renewal for a certificate nothing
used (TLS terminates at Cloudflare's edge), delaying tunnel recovery. The
replacement is two small containers: `twenty-caddy` (HTTP-only reverse proxy,
`caddy/Caddyfile`) and `twenty-cloudflared` (`cloudflared/config.yml` +
`credentials.json`). Hostname changes are made in group_vars
(`twenty_domain`/`twenty_domain_aliases`) and flow into both templates; the
tunnel credential is created once with `cloudflared tunnel create` and only
verified by the role. SWAG-era secrets (cf_tunnel_password, cf_api_token,
cf_zone_id, cf_account_id) are retired.

## Node Allocation

| Hostname | VMID | Initial Node | Mgmt IP | Transfer IP | Role | Environment |
| -------- | ---- | ------------ | ------- | ----------- | ---- | ----------- |
| test.app.musa | 1095 | joseph | 192.168.5.95 | 192.168.11.95 | app | test |
| prod.app.musa | 1090 | joseph | 192.168.5.90 | 192.168.11.90 | app | prod (reserved, not yet deployed) |

Single LXC, registered with Proxmox HA. If the initial node fails, Proxmox
restarts the LXC on another cluster node (everette, maxwell, …) automatically.
Disk lives on Ceph so failover does not copy data; IP and hostname are preserved.

**VMID Allocation:** 4-digit TSSS pattern (1xxx LXC + IP octet .190)
**Reference:** jacaranda-inventory registry (services/musa.yaml)

## Resources

| Resource | Value | Notes |
| -------- | ----- | ----- |
| Cores | 4 | Twenty CRM needs more than default |
| Memory | 4096 MB | Higher than typical LXC |
| Disk | 20G | Database + backups |
| Storage | Ceph | From `infra.yaml` (`storage.ceph.name`) |
| Nesting | true | Required for Docker-in-LXC |

## Directory Structure

```text
jacaranda-musa/
├── CLAUDE.md                          # This file
├── .gitignore                         # Excludes logs, terraform state
├── infra.yaml                         # Topology source of truth (VLANs, storage, Proxmox)
├── justfile                           # Module-based recipes (mod test, mod prod)
├── test.just                          # Test environment recipes
├── prod.just                          # Production placeholder
├── mise.toml                          # Tool versions (just, opentofu, uv, pre-commit)
├── .mise.local.toml.example           # 1Password Connect template
├── pyproject.toml                     # Python 3.12 + Ansible 2.17
├── scripts/
│   ├── op-read                        # 1Password secret reading script
│   └── op-connect.sh                  # 1Password Connect injection
├── lib/                               # submodule @ v1.5.0 (jacaranda-shared-libs)
│   └── infrastructure/
│       ├── just/                      # Shared justfile utilities
│       └── terraform/modules/         # Shared terraform modules (LXC, vmid-ranges)
├── terraform/
│   ├── main.tf                        # LXC module (uses lib/infrastructure/terraform/modules/lxc)
│   ├── variables.tf                   # Instance, infrastructure vars
│   ├── outputs.tf                     # DNS entries, instance details
│   └── envs/
│       ├── test/
│       │   └── main.tf                # Single instance: VMID 1095, joseph (HA-managed)
│       └── prod/
│           └── main.tf                # Placeholder (provider config only)
└── ansible/
    ├── ansible.cfg                    # Pipelining, YAML output, SSH multiplexing
    ├── inventory/
    │   ├── .gitkeep                   # test.yaml auto-generated by Terraform
    │   └── group_vars/
    │       └── all.yaml               # Shared non-secret variables
    ├── playbooks/
    │   └── deploy.yaml                # Runs musa role on musa group
    └── roles/musa/
        ├── defaults/main.yaml         # Role defaults (versions, domains)
        ├── tasks/main.yaml            # Docker install, GHCR login, templates, start, verify
        ├── handlers/main.yaml         # Stack restart handler
        └── templates/
            ├── cloudflare.ini.j2      # Cloudflare API token for certbot DNS-01 validation
            ├── docker-compose.yaml.j2 # 10-service stack (Twenty, PG, Redis, sidecars, Caddy, cloudflared)
            ├── env.j2                 # .env for Twenty's env_file directive
            └── twenty.conf.j2         # nginx proxy config → server:3000
```

## What Terraform Does vs Ansible

**Terraform creates:**

- 1x LXC container on Proxmox (joseph initial placement, VMID 1095)
- Dual NIC: eth0 (mgmt .5.95) + eth1 (transfer .11.95)
- Docker nesting enabled (`nesting=true`)
- Proxmox HA registration via `ha-manager add` (failover to any cluster node)
- Ansible inventory written to `ansible/inventory/test.yaml`
- DNS outputs (A records + CNAMEs) for Pi-hole integration (handled by hub)

**Ansible configures:**

- Docker + Docker Compose plugin installation
- GHCR authentication (for private backup/rollup/webhook images)
- Docker Compose stack: Caddy + cloudflared + Twenty CRM + PostgreSQL + Redis + backup + rollup + webhooks
- 4 configuration templates:
  - `cloudflare.ini.j2` — Cloudflare API token for certbot DNS-01 validation
  - `docker-compose.yaml.j2` — Full 9-container stack
  - `env.j2` — Twenty CRM environment variables
  - `twenty.conf.j2` — Nginx reverse proxy config
- Health verification: Twenty /healthz locally, then https://<domain>/healthz through the tunnel

## Secrets

**1Password Items Required:**

| Item | Field | Purpose |
| ---- | ----- | ------- |
| `musa-project-crm-test` | `cf_tunnel_token` | Cloudflare Tunnel JWT for external access |
| `musa-project-crm-test` | `pg_password` | PostgreSQL password (local container DB) |
| `musa-project-crm-test` | `app_secret` | Twenty CRM application secret |
| `musa-project-crm-test` | `encryption_key` | At-rest envelope key for OAuth tokens, TOTP secrets, app variables (Twenty v2.5+; raw secret, generate via `openssl rand -base64 32`) |
| `cloudflare` | `api_token` | Cloudflare API for DNS validation (Let's Encrypt) |
| `cloudflare` | `zone_id` | Cloudflare zone ID for joeseymour.io |
| `cloudflare` | `account_id` | Cloudflare account ID |
| `github` | `pat` | GHCR read:packages token for private images |
| `Jacaranda Proxmox Deploy` | `api token` | Proxmox API token secret (`TF_VAR_proxmox_api_token_secret`); shared with foundation |
| `musa-project-test` | `public key` | SSH public key injected into LXC cloud-init (`TF_VAR_ssh_public_key`) |
| `opentofu` | `password` | OpenTofu state encryption passphrase |

**Secrets flow:**

```text
justfile (op-read script) → ansible -e "var=val" → Jinja2 templates → .env + compose on LXC
```

**Check secrets before deployment:**

```bash
just check-secrets  # Verifies all required 1Password items exist
```

## Deployment Workflow

### Prerequisites

1. **1Password items exist:** `just check-secrets` (all green)
2. **Cloudflare Tunnel created:** Dashboard → Zero Trust → Tunnels → `musa-project-test`
   - Public hostname: `musa-project-test.joeseymour.io` → `http://localhost:80`
   - Token stored in `op://Homelab/musa-project-crm-test/cf_tunnel_token`
3. **DNS configured:** Hub repository manages Pi-hole DNS (reads dns_entries/cname_entries outputs)
4. **Shared-libs submodule initialized:** `git submodule update --init`

### Deploy (Test Environment)

```bash
# Full deployment (Terraform + Ansible)
just test::full

# Or step by step:
just test::init          # Initialize OpenTofu
just test::plan          # Preview changes
just test::apply         # Create LXC container
# Wait 30s for boot
just test::deploy        # Configure and start services

# Validate
just test::validate
```

### Update Existing Deployment

```bash
just test::deploy              # Re-run Ansible only
VERBOSE=1 just test::deploy    # Verbose output
DEBUG=1 just test::deploy      # Maximum debug output
```

### Upgrade Providers

```bash
just upgrade  # Runs tofu init -upgrade for test and prod environments
```

## Common Operations

### Check Service Status

```bash
just test::validate
just test::logs

# SSH to node
ssh root@test.app.musa.mgmt.home.arpa "docker ps"
ssh root@test.app.musa.mgmt.home.arpa "docker logs server --tail=20"
ssh root@test.app.musa.mgmt.home.arpa "docker logs twenty-caddy --tail=20"
ssh root@test.app.musa.mgmt.home.arpa "docker logs twenty-cloudflared --tail=20"
```

### Restart Services

```bash
ssh root@test.app.musa.mgmt.home.arpa "cd /opt/musa && docker compose restart"
ssh root@test.app.musa.mgmt.home.arpa "docker restart server"
ssh root@test.app.musa.mgmt.home.arpa "docker restart twenty-caddy twenty-cloudflared"
```

### Test External Access

```bash
# Via Cloudflare Tunnel
curl -I https://musa-project-test.joeseymour.io

# Local (from LXC)
ssh root@test.app.musa.mgmt.home.arpa "curl -I http://localhost:80"
ssh root@test.app.musa.mgmt.home.arpa "curl -s http://localhost:3000/healthz"
```

### View Backups

```bash
ssh root@test.app.musa.mgmt.home.arpa "ls -lh /opt/musa/backups/"
ssh root@test.app.musa.mgmt.home.arpa "docker logs twenty-backup --tail=20"
```

## DO vs DON'T

### DO

- Use `just check-secrets` before first deployment
- Use `root@test.app.musa.mgmt.home.arpa` for SSH (LXC containers use root)
- Let Ansible manage all config files on the LXC
- Run `just test::deploy` to update (idempotent)
- Use `just upgrade` to update OpenTofu providers
- Update shared-libs submodule: `git submodule update --remote lib`

### DON'T

- Commit secrets or tunnel tokens to git
- Modify the LXC container in Proxmox UI (Terraform-managed)
- Edit `ansible/inventory/*.yaml` files manually (auto-generated by Terraform)
- Edit files directly on the LXC (they'll be overwritten by next deploy)
- Hardcode IP allocations or VLAN topology in `*.tf` files (use `infra.yaml` for VLAN/storage/Proxmox topology and the jacaranda-inventory registry for IP allocations)
- Modify shared-libs content (propose changes to jacaranda-shared-libs repo)

## Agent Boundaries

**What this agent CAN do (positive boundaries):**

- Modify files within jacaranda-musa repository only
- Configure Musa LXC via terraform and ansible
- Update Twenty CRM version, Caddy/cloudflared configuration, docker-compose stack
- Add/remove container services (backup, rollup, webhook workers)
- Update Cloudflare Tunnel ingress and Caddy proxy settings
- Run deployments via `just test::deploy` (user manually triggers)
- Add validation checks and troubleshooting recipes
- Update CLAUDE.md documentation for musa service
- Update mise tool versions, Python dependencies, Ansible collections
- Add new 1Password secret references (user creates items)
- Export dns_entries/cname_entries outputs (hub aggregates for Pi-hole)

**What this agent CANNOT do (negative boundaries):**

- Modify other service repositories (jacaranda-foundation, jacaranda-redis, jacaranda-pihole, etc.)
- Change base infrastructure (VLANs, DNS servers, Proxmox config) at the source — edit musa's `infra.yaml` to mirror foundation when topology changes, or coordinate updates to `jacaranda-foundation/infra.yaml` upstream
- Allocate IPs or VMIDs — must reference NetBox or coordinate with user
- Create DNS records directly — outputs dns_entries/cname_entries, hub aggregates
- Modify shared-libs (jacaranda-shared-libs) — propose changes to that repo instead
- Bypass shared modules — always consume LXC + vmid-ranges modules via lib/ submodule
- Run `just apply` or `just deploy` without explicit user request
- Create GitHub releases or version tags without user approval

**Skills-only policy:**

- **VMID allocation:** Use NetBox IPAM skill or ask user for next available VMID
- **IP allocation:** Use NetBox IPAM skill or ask user for IP assignment
- **DNS records:** Export dns_entries/cname_entries outputs, hub aggregation handles Pi-hole registration
- **Base infrastructure access:** Read `infra.yaml` at the repo root (VLANs, storage, Proxmox token id, LXC template). Secrets (Proxmox token secret, SSH key) come from 1Password via TF_VAR injection in test.just.
- **Terraform modules:** Always source from lib/ submodule at tagged version (currently v1.5.0)

**If a skill is missing:** Ask user for guidance rather than creating manual workarounds.

## Terraform Modules

**Shared modules consumed from lib/ submodule:**

| Module | Source | Purpose |
| ------ | ------ | ------- |
| lxc | `lib/infrastructure/terraform/modules/lxc` | LXC container creation, SSH cert signing, inventory generation |
| vmid-ranges | `lib/infrastructure/terraform/modules/vmid-ranges` | VMID allocation validation |

**Infrastructure topology lives in `infra.yaml`** at the repo root — VLANs, storage, LXC template, Proxmox token id, TLS setting. This mirrors `jacaranda-foundation/infra.yaml` for the same homelab. Secrets (Proxmox API token secret, SSH key) come from 1Password and are injected via TF_VAR in test.just. The deprecated `base-infra` module (which read `data "terraform_remote_state"` from the no-longer-existing jacaranda-infra repo) is not used.

**Module versioning:** lib/ submodule pinned to v1.5.0. Update via `git submodule update --remote lib` and commit new submodule reference.

## Dependencies

| Dependency | Purpose | Location |
| ---------- | ------- | -------- |
| 1Password Connect | Secret injection at deploy time | Hub managed |
| Cloudflare Tunnel | External access at musa-project-test.joeseymour.io | User configured |
| Pi-hole DNS | `.mgmt.home.arpa` hostname resolution | Hub managed (aggregates dns_entries/cname_entries) |
| GHCR | Private container images (backup, rollup, webhook) | User authenticated |
| Base infrastructure | Proxmox API, VLANs, storage, LXC template | `infra.yaml` (repo root) + 1Password for secrets |
| DNS server | Bootstrap resolver IP for the LXC | `jacaranda-inventory/data/services/dns.yaml` read at plan-time |
| Shared libraries | Terraform modules, justfile utilities | lib/ submodule (jacaranda-shared-libs v1.5.0) |

## Related Documentation

| Topic | Location |
| ----- | -------- |
| Shared libraries repo | https://github.com/poindexter12/jacaranda-shared-libs |
| Twenty CRM upstream | https://github.com/twentyhq/twenty |
| Caddy | https://caddyserver.com/docs/ |
| Cloudflare Tunnel | https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/ |
| Docker-in-LXC | https://pve.proxmox.com/wiki/Linux_Container#_nesting |

## Troubleshooting

### Caddy or cloudflared fails to start

```bash
ssh root@test.app.musa.mgmt.home.arpa "docker logs twenty-caddy --tail=50"
ssh root@test.app.musa.mgmt.home.arpa "docker logs twenty-cloudflared --tail=50"
ssh root@test.app.musa.mgmt.home.arpa "cat /opt/musa/caddy/Caddyfile"
ssh root@test.app.musa.mgmt.home.arpa "cat /opt/musa/cloudflared/config.yml"
```

### Twenty CRM not accessible

**Check container status:**

```bash
ssh root@test.app.musa.mgmt.home.arpa "docker ps"  # All 10 containers should be Up
ssh root@test.app.musa.mgmt.home.arpa "docker logs server --tail=50"
```

**Check health endpoint:**

```bash
ssh root@test.app.musa.mgmt.home.arpa "curl -s http://localhost:3000/healthz"
```

**Check the Caddy proxy:**

```bash
ssh root@test.app.musa.mgmt.home.arpa "docker logs twenty-caddy --tail=30"
```

### Cloudflare Tunnel not connecting

**Check the tunnel:**

```bash
ssh root@test.app.musa.mgmt.home.arpa "docker logs twenty-cloudflared --tail=30"
ssh root@test.app.musa.mgmt.home.arpa "ls -la /opt/musa/cloudflared/"  # config.yml + credentials.json
```

**Verify tunnel configuration in Cloudflare Dashboard:**

- Zero Trust → Networks → Tunnels
- Ensure `musa-project-test` tunnel exists
- Public hostname configured: `musa-project-test.joeseymour.io` → `http://localhost:80`

### Database issues

**Check PostgreSQL container:**

```bash
ssh root@test.app.musa.mgmt.home.arpa "docker logs db --tail=50"
ssh root@test.app.musa.mgmt.home.arpa "docker exec db pg_isready -U twenty"
```

**Check Twenty CRM database connection:**

```bash
ssh root@test.app.musa.mgmt.home.arpa "docker logs server | grep -i database"
ssh root@test.app.musa.mgmt.home.arpa "cat /opt/musa/.env | grep PG_"
```

### Backups not running

**Check backup container:**

```bash
ssh root@test.app.musa.mgmt.home.arpa "docker logs twenty-backup --tail=50"
ssh root@test.app.musa.mgmt.home.arpa "ls -lh /opt/musa/backups/"
```

**Manual backup:**

```bash
ssh root@test.app.musa.mgmt.home.arpa "docker exec twenty-backup /backup.sh"
```
