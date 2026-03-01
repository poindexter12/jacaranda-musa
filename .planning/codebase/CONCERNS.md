# Codebase Concerns

**Analysis Date:** 2026-02-28

## Security & Secrets Management

**Sensitive credentials in environment context:**
- Issue: Passwords and API tokens (cf_tunnel_token, cf_api_token, pg_password, app_secret, ghcr_pat) are passed via Ansible extra-vars from 1Password. While secrets are marked with `no_log: true` in tasks, they remain visible in environment variables within containers.
- Files: `ansible/roles/musa/tasks/main.yaml` (lines 79-85, 105-129), `ansible/roles/musa/templates/docker-compose.yaml.j2` (lines 176, 187, 97-98)
- Impact: Container escape or log aggregation could expose secrets. Cloudflare credentials are particularly sensitive (DNS API access).
- Fix approach: Migrate to Docker secrets management or 1Password Connect integration. Use `secrets:` directive in docker-compose instead of environment variables. This requires a separate 1Password Connect server or HashiCorp Vault integration.

**PostgreSQL password exposed in multiple places:**
- Issue: `pg_password` appears in plaintext in three locations: environment variables, .env file, and docker-compose.yaml template.
- Files: `ansible/roles/musa/templates/env.j2` (line 6), `ansible/roles/musa/templates/docker-compose.yaml.j2` (lines 21, 97-98), `ansible/roles/musa/tasks/main.yaml` (line 82)
- Impact: Password visible in container env, logs, and config files. Backup container also receives the password.
- Fix approach: Use PostgreSQL `.pgpass` file or connection pooling with built-in credential handling. Store pg_password in docker secret and reference only where needed.

**GHCR PAT stored as environment variable:**
- Issue: GitHub PAT is passed as environment variable to ansible task for docker login, then immediately used but not explicitly cleared.
- Files: `ansible/roles/musa/tasks/main.yaml` (lines 79-85), `test.just` (line 56)
- Impact: PAT may remain in bash history or process memory. If container is compromised, attacker gains private image access.
- Fix approach: Use `docker login` with stdin only (already done), but add explicit credential cleanup. Better: use GitHub OIDC token exchange instead of long-lived PAT.

**Cloudflare tunnel token in SWAG environment:**
- Issue: `CF_REMOTE_MANAGE_TOKEN` passed as plaintext environment variable to SWAG container. Token grants remote tunnel management access.
- Files: `ansible/roles/musa/templates/docker-compose.yaml.j2` (line 176)
- Impact: Container compromise exposes Cloudflare Zero Trust tunnel. Attacker could intercept/redirect traffic.
- Fix approach: Mount Cloudflare tunnel credentials as a secret file instead. SWAG mod should support file-based config.

## Infrastructure & Deployment Risks

**Hard-coded resource limits insufficient for production:**
- Issue: Fixed 4 cores / 4GB memory for all environments. Twenty CRM with 9 containers shares fixed resources. Backup, rollup, and webhook workers compete for CPU/memory with main server.
- Files: `ansible/roles/musa/defaults/main.yaml` (line 7, 8), `terraform/envs/test/main.tf` (lines 100-102), `terraform/variables.tf` (lines 70-80)
- Impact: Under load (data import, webhook surge), services will throttle or OOM-kill. Database backups may block main application. Rollup cron can cause slowdowns at 2 AM.
- Fix approach: Make cores/memory configurable per environment (test=4/4GB, prod=8/16GB). Add resource limits/requests to each docker-compose service. Monitor memory pressure and add swap or scale vertically.

**Stateful volumes with no explicit backup strategy:**
- Issue: PostgreSQL data, Redis, SWAG certificates stored in local docker volumes (db-data, server-local-data, swag-config). Only db-data has a backup container.
- Files: `ansible/roles/musa/templates/docker-compose.yaml.j2` (lines 190-198)
- Impact: Loss of SWAG SSL certificates means manual Let's Encrypt renewal. Loss of server-local-data (Twenty local storage) means reupload of all attachments. No backup of redis (sessions/cache loss is tolerable but not tested).
- Fix approach: Add volume backup container for swag-config. Verify 20-backup is running and test restore procedure. Consider cross-backup of critical volumes to external storage.

**Health checks have loose timeout/retry logic:**
- Issue: Health checks for Twenty CRM (lines 60-64, docker-compose) use 30s interval with 3 retries = 90s max detection time. SWAG health check in Ansible uses `curl` with no explicit timeout.
- Files: `ansible/roles/musa/templates/docker-compose.yaml.j2` (lines 59-64, 137-142), `ansible/roles/musa/tasks/main.yaml` (lines 154-162)
- Impact: Service degradation may not be detected for 90+ seconds. Zombie containers can remain running if health check fails intermittently.
- Fix approach: Tighten timeouts to 10s, increase retries to 5 for total 50s detection window. Add explicit curl timeout in Ansible health check.

**Container restart policy too broad:**
- Issue: All containers use `restart: unless-stopped`, meaning failed containers will restart indefinitely (default max-retries=unlimited).
- Files: `ansible/roles/musa/templates/docker-compose.yaml.j2` (all services)
- Impact: If a configuration error exists, container will restart in a loop, consuming CPU and filling logs. No feedback to operator.
- Fix approach: Change to `restart: on-failure:3` with delay. Add alerting/logging for restart loops.

## Configuration & Deployment Gaps

**No database migration validation:**
- Issue: Worker container has `DISABLE_DB_MIGRATIONS: "true"` (line 80, docker-compose), but no explicit migration task runs before main server starts. Server container runs migrations on startup (implicit), but failure path is unclear.
- Files: `ansible/roles/musa/templates/docker-compose.yaml.j2` (lines 78-82)
- Impact: If Twenty CRM version bump includes schema changes, and schema migration fails, main server may fail to start. Downtime risk on version upgrades.
- Fix approach: Add explicit pre-flight migration task in Ansible that runs before docker compose up. Make migration validation part of health check.

**No validation of Twenty CRM version compatibility:**
- Issue: `twenty_tag: "v1.17.0"` is hardcoded in defaults. Upgrading version requires manual edit; no version compatibility matrix with dependencies (PostgreSQL 16, Redis 7, Node, etc.).
- Files: `ansible/roles/musa/defaults/main.yaml` (line 13)
- Impact: Version mismatch could introduce API breakage or incompatible container images. No rollback procedure documented.
- Fix approach: Add version compatibility matrix as YAML. Validate version during deploy. Implement blue-green deployment or rollback recipe.

**No rollback procedure for configuration changes:**
- Issue: Handlers use `docker compose up -d --force-recreate` (handlers/main.yaml line 6), which recreates all containers if any config changes. No backup of previous docker-compose or .env versions.
- Files: `ansible/roles/musa/handlers/main.yaml`, `ansible/roles/musa/tasks/main.yaml` (lines 143-148)
- Impact: Bad config change (typo in env var, nginx config error) takes down entire stack. No easy rollback without re-running full deployment.
- Fix approach: Add config versioning/backup. Create rollback recipe that restores last-known-good docker-compose. Use config management to validate nginx config before reload.

**Ansible task for Docker startup relies on idempotency assumption:**
- Issue: Line 144-148 in tasks/main.yaml runs `docker compose up -d` with `changed_when: false`, assuming it's idempotent. If server fails to start, subsequent runs won't retry.
- Files: `ansible/roles/musa/tasks/main.yaml` (lines 143-148)
- Impact: If docker compose stack fails to start due to network issues or port conflicts, subsequent idempotent runs won't detect the failure.
- Fix approach: Remove `changed_when: false` and add proper error checking. Better: use `docker compose up -d --wait` if version supports it.

## Operational Concerns

**No log aggregation or centralized monitoring:**
- Issue: All containers log to local driver with 10m rotation / 3 files max (docker-compose.yaml.j2 lines 5-10). No forwarding to centralized log store (ELK, Loki, syslog).
- Files: `ansible/roles/musa/templates/docker-compose.yaml.j2` (lines 5-10)
- Impact: Historical logs lost when rotated. Troubleshooting requires SSH to container. No metrics on service health or performance trends.
- Fix approach: Add syslog or fluentd container to forward logs to centralized store. Configure container logging driver as syslog.

**Backup container has no alerting on failure:**
- Issue: `twenty-backup` container runs daily (implicit cron), but no notification if backup fails. Logs are local only.
- Files: `ansible/roles/musa/templates/docker-compose.yaml.j2` (lines 84-101)
- Impact: Backup job could fail silently for days. Data loss risk undetected.
- Fix approach: Add webhook/email notification on backup completion status. Implement backup verification (test restore). Add backup age check to health endpoint.

**No automated testing of Cloudflare Tunnel connectivity:**
- Issue: Tunnel token is passed to SWAG, but no validation that tunnel actually connects. `just test::validate` only checks local health endpoints.
- Files: `test.just` (lines 81-113), `ansible/roles/musa/tasks/main.yaml` (lines 164-171)
- Impact: Cloudflare Tunnel could be misconfigured or token expired, but external access would silently fail. Users may not notice until reported.
- Fix approach: Add curl test to external FQDN (musa-project-crm-test.joeseymour.io) in validation recipe. Validate tunnel status via Cloudflare API.

**Hardcoded domain in multiple files, no env abstraction:**
- Issue: `musa-project-crm-test.joeseymour.io` appears in `defaults/main.yaml`, nginx template, and docker-compose template. No parameterization for domain.
- Files: `ansible/roles/musa/defaults/main.yaml` (line 14), `ansible/roles/musa/templates/twenty.conf.j2` (line 10), `ansible/roles/musa/templates/docker-compose.yaml.j2` (lines 58, 177)
- Impact: Changing domain requires edits in 3 places. No easy way to deploy same config to multiple domains.
- Fix approach: Move all domain/URL config to `group_vars/all.yaml` or role vars. Use single source of truth.

## Container Image Concerns

**Musa custom containers pinned to `latest` tag:**
- Issue: Backup, rollup, and webhook containers use `ghcr.io/poindexter12/musa-project-twenty-crm/*:latest` (lines 85, 104, 119, 145 in docker-compose).
- Files: `ansible/roles/musa/templates/docker-compose.yaml.j2` (lines 85, 104, 119, 145)
- Impact: Deployments are non-reproducible. A new `latest` push anywhere in the repo will silently pull newer code on next `docker compose pull`. Security updates or breaking changes deploy without notification.
- Fix approach: Pin to specific semantic versions (e.g., `ghcr.io/poindexter12/musa-project-twenty-crm/backup:v1.0.0`). Use renovate or dependabot to auto-update with PRs.

**Base image tags not validated for security:**
- Issue: SWAG uses `lscr.io/linuxserver/swag:latest`, Twenty uses `twentycrm/twenty:{{ twenty_tag }}` but no image digest verification or vulnerability scanning.
- Files: `ansible/roles/musa/templates/docker-compose.yaml.j2` (lines 44, 163)
- Impact: Image could be compromised at pull time. No guarantee image hasn't been replaced.
- Fix approach: Pin to image digest (e.g., `swag@sha256:abc123...`). Add image vulnerability scanning to deployment pipeline.

**No Docker image pull policy validation:**
- Issue: Containers will pull images on every deploy if `imagePullPolicy` not set. For `latest` tags, this is unpredictable.
- Files: `ansible/roles/musa/templates/docker-compose.yaml.j2` (docker-compose doesn't expose pull_policy directly)
- Impact: Network outage during deploy could leave stale/broken images running. Private images (backup, rollup, webhook) require GHCR auth to pull.
- Fix approach: Set explicit pull_policy in compose (if supported in version). Pre-pull images in Ansible before docker compose up.

## Scaling & Performance Concerns

**Redis configured with `maxmemory-policy noeviction`:**
- Issue: Redis will fail writes if it runs out of memory instead of evicting old data (line 34, docker-compose).
- Files: `ansible/roles/musa/templates/docker-compose.yaml.j2` (line 34)
- Impact: If redis memory limit is hit (shared with other containers), session cache and job queue writes fail. Server degradation or crashes possible.
- Fix approach: Set explicit maxmemory limit and use `allkeys-lru` or `volatile-lru` policy. Monitor redis memory usage.

**PostgreSQL 16 with no explicit resource allocation:**
- Issue: PostgreSQL container has no memory limit. With shared 4GB host memory, database can OOM-kill other services.
- Files: `ansible/roles/musa/templates/docker-compose.yaml.j2` (lines 14-29)
- Impact: Large query or data import could consume all memory, causing backup/rollup to OOM. Database recovery slow.
- Fix approach: Add `deploy.resources.limits.memory` to PostgreSQL service. Tune `shared_buffers`, `effective_cache_size` based on container memory.

**No query performance monitoring or slow query logging:**
- Issue: PostgreSQL runs with default logging. No slow query log configured.
- Files: `ansible/roles/musa/templates/docker-compose.yaml.j2` (lines 14-29)
- Impact: Performance degradation on large datasets undetected. N+1 queries from Twenty CRM not visible.
- Fix approach: Enable PostgreSQL slow query log. Mount logs to persistent volume. Integrate with centralized logging.

## Dependency & Version Management

**Hardcoded Ubuntu template version:**
- Issue: `ubuntu-24.04-standard_24.04-2_amd64.tar.zst` template is hardcoded (terraform/envs/test/main.tf line 96). New templates require manual update.
- Files: `terraform/envs/test/main.tf` (line 96)
- Impact: If template becomes unavailable or deprecated, deploy fails. No automatic patching for LXC base OS security updates.
- Fix approach: Use data source to fetch latest template dynamically. Or move template selection to variables.tfvars.

**OpenTofu provider pinned to non-stable RC version:**
- Issue: Proxmox provider pinned to `3.0.2-rc07` (terraform/envs/test/main.tf line 18). RC versions are pre-release with limited testing.
- Files: `terraform/envs/test/main.tf` (line 18)
- Impact: Bug fixes or breaking changes in RC may require code changes. Not supported for production.
- Fix approach: Upgrade to stable version (3.0.2 or later). Track provider updates with renovate.

**Ansible collections not explicitly pinned:**
- Issue: `ansible.cfg` and roles use default collections without version specification. No `requirements.yml` file.
- Files: `ansible/roles/musa/tasks/main.yaml` (uses ansible.builtin, no version)
- Impact: Collection updates could change behavior. Bug fixes or deprecations in collection modules.
- Fix approach: Create `requirements.yml` with pinned collection versions. Pin in `ansible.cfg`.

## Data & State Management

**No documented backup restore procedure:**
- Issue: Backup container creates files, but no documented or tested restore procedure.
- Files: `ansible/roles/musa/templates/docker-compose.yaml.j2` (lines 84-101)
- Impact: Backups exist but may not be usable when needed. Disaster recovery untested.
- Fix approach: Document restore procedure. Add automated restore test (weekly: restore to separate DB and verify).

**Docker volumes use local driver, no distributed storage:**
- Issue: All volumes stored on LXC container filesystem (local:// driver). No redundancy if container filesystem corrupts.
- Files: `ansible/roles/musa/templates/docker-compose.yaml.j2` (lines 190-198)
- Impact: Database corruption or filesystem error = data loss. No way to recover if LXC dies.
- Fix approach: Use Ceph or NFS volumes for database/backups. Move critical data off-LXC.

**State file management for Terraform not documented:**
- Issue: `.gitignore` excludes `*.tfstate`, but no documentation on where state is stored or backed up.
- Files: `.gitignore` (lines 2-3)
- Impact: Terraform state loss = infrastructure consistency loss. Re-creating resources could fail or create duplicates.
- Fix approach: Document terraform state backend (probably local disk in this case). Implement backup of state files. Consider remote state (Consul, S3, etc.).

---

*Concerns audit: 2026-02-28*
