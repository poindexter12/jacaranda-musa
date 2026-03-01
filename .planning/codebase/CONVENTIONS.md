# Coding Conventions

**Analysis Date:** 2026-02-28

## Naming Patterns

**Files:**
- Terraform files: `*.tf` (no extension variations)
- Ansible playbooks: `*.yaml` (not `*.yml`)
- Ansible role structure: `roles/{name}/{tasks,handlers,defaults,templates}/main.yaml`
- Shell scripts: `*.sh` with `#!/bin/bash` shebang
- Justfiles: `justfile`, `test.just`, `prod.just` (module-based organization)
- Jinja2 templates: `*.j2` (e.g., `docker-compose.yaml.j2`, `env.j2`)
- Configuration: `ansible.cfg`, `mise.toml`, `pyproject.toml`

**Terraform:**
- Variables: descriptive camelCase with underscores for compound names (`pg_password`, `cf_tunnel_token`, `app_data_dir`)
- Resource names: snake_case (e.g., `local.musa_instances`, `module.base_infra`, `module.vmid`)
- Locals: lowercase snake_case (e.g., `local.env`, `local.musa_instances`, `local.base`)
- Module sources: relative paths using `..` (e.g., `"../lib/infrastructure/terraform/modules/lxc"`)

**Ansible:**
- Task names: Title Case describing the action (e.g., "Install Docker prerequisites", "Deploy Docker Compose stack")
- Variable names: snake_case (e.g., `app_data_dir`, `cf_tunnel_token`, `pg_password`, `twenty_domain`)
- Handler names: descriptive with action verb (e.g., "restart musa stack")
- Role names: kebab-case (e.g., `musa`)
- Group names: kebab-case (e.g., `musa`)
- Task tags: lowercase (e.g., `[always]`, `[deploy]`, `[verify]`)

**Shell Scripts:**
- Function names: lowercase with underscores (e.g., `check_token()`, `api_request()`, `get_vault_id()`)
- Variables: UPPER_CASE for environment variables (e.g., `OP_CONNECT_TOKEN`, `OP_CONNECT_SERVERS`)
- Variables: lowercase_with_underscores for local variables (e.g., `vault_id`, `item_id`, `cache_file`)

**Just Recipes:**
- Recipe names: lowercase with optional double colons for module organization (e.g., `test::full`, `test::deploy`, `check-secrets`)
- Descriptions: Brief English description on same line as recipe definition
- Section headers: UPPERCASE with equals signs for visual separation

## Code Style

**Formatting:**
- YAML indentation: 2 spaces (consistent across Ansible, Docker Compose, configs)
- Terraform: 2-space indentation, `terraform fmt` enforced via pre-commit
- Shell: 4-space indentation, `shellcheck` enforced via pre-commit
- Line length: max 160 characters (yamllint rule)

**Pre-commit Hooks:**
- Tool: `pre-commit` v4.0.1 (managed via mise)
- Configuration: `lib/.lint/pre-commit-config.yaml` (distributed via shared-libs)
- Hooks applied:
  - `trailing-whitespace`, `end-of-file-fixer`, `check-yaml` (general)
  - `yamllint` with custom rules (line-length: 160, document-start: disabled)
  - `shellcheck` (shell linting, excludes `/templates/`)
  - `terraform_fmt` (Terraform formatting, excludes `encryption.tf`)
  - `markdownlint-cli2` (Markdown linting with auto-fix)
  - Custom hooks: `validate-vmid-pattern`, `validate-op-secrets`, `no-yml-extension`, `validate-ssh-host-cert`

**Installation:**
```bash
cp lib/.lint/pre-commit-config.yaml .pre-commit-config.yaml
pre-commit install
```

## Import Organization

**Terraform:**

Imports use relative paths from the root Terraform module:

```hcl
# Example: terraform/envs/test/main.tf
module "base_infra" {
  source = "../../../lib/infrastructure/terraform/modules/base-infra"
}

module "musa" {
  source = "../.."  # Parent directory (terraform/)
}
```

Order:
1. `required_version` and `required_providers` block
2. `module` declarations (base infrastructure first, then service modules)
3. `locals` for instance configuration
4. `check` blocks for validation
5. `provider` configuration
6. Additional resources/modules
7. `output` declarations

**Ansible:**

Imports use relative paths and module structure:

```yaml
# Example: ansible/playbooks/deploy.yaml
- hosts: musa
  become: true
  roles:
    - musa  # Resolves to roles/musa/
```

Role structure:
- `defaults/main.yaml` — Default values
- `tasks/main.yaml` — Main tasks
- `handlers/main.yaml` — Event handlers
- `templates/*.j2` — Jinja2 templates

**Just:**

Imports use relative paths from justfile root:

```just
import 'lib/infrastructure/just/styles.just'
import 'lib/infrastructure/just/secrets.just'
mod test
mod prod
```

## Error Handling

**Patterns:**

**Terraform:**
- Use `check` blocks for validation (example: `check "vmid_allocation"` validates VMID ranges)
- Failure messages include reference documentation (example: "See .claude/skills/vmid-allocation.md")
- Use `condition` assertions with `alltrue([])` for multi-item validation

**Ansible:**
- Use `ansible.builtin.assert` for required variables validation
- Include `fail_msg` and `success_msg` for clarity
- Use `changed_when: false` to prevent marking runs as "changed" on read-only tasks
- Use `until` + `retries` + `delay` for health checks (example: wait for SWAG with 30 retries, 5s delay)
- Tag health checks with `[verify]` for selective execution
- Use `no_log: true` for tasks handling secrets

**Shell Scripts:**
- Set strict mode: `set -euo pipefail`
- Use `error()` function for error messages with exit code 1
- Use `debug()` function for conditional debug output (`OP_CONNECT_DEBUG=1`)
- Validate inputs before processing (example: check `OP_CONNECT_TOKEN` exists)
- Use `||` and `&&` for conditional execution
- Cache long-lived data with expiration (example: 1-hour cache for vault IDs)

**Just Recipes:**
- Use `#!/usr/bin/env bash` shebang with `set -euo pipefail` for shell recipes
- Use `[confirm(...)]` attribute for destructive operations
- Use `printf` with ANSI color codes for output (example: `'{{ GREEN }}'`, `'{{ RED }}'`, `'{{ CYAN }}'`)
- Use color variables from `lib/infrastructure/just/styles.just` (must import)

## Logging

**Framework:** Native tools (Ansible logging, shell echo, terraform output)

**Patterns:**

**Ansible:**
- Configure via `ansible.cfg`: `stdout_callback = default`, `result_format = yaml`, `callbacks_enabled = timer`
- Log to file: set `ANSIBLE_LOG_PATH` environment variable (example: `logs/ansible-YYYYMMDD-HHMMSS.log`)
- Verbose output: use `-v`, `-vv`, `-vvv` flags
- Suppress output: use `no_log: true` for secrets, `changed_when: false` for read-only tasks
- Output task results: use `register` to capture output for later display

**Shell Scripts:**
- Simple logging: use `echo` for standard output, `>&2` for stderr
- Debug output: conditional via environment variable (example: `OP_CONNECT_DEBUG=1`)
- Function prefixes: `[DEBUG]`, `[ERROR]` for consistency

**Just Recipes:**
- Status messages: use `printf` with ANSI color codes
- Progress: use emoji/symbols for visual clarity (example: `→`, `✓`, `MISSING`)
- Multi-step operations: print step headers with `---` separators

## Comments

**When to Comment:**
- Complex shell logic (e.g., API failover, cache expiration calculations)
- Non-obvious Terraform module usage (e.g., why `nesting=true` is required for Docker-in-LXC)
- Prerequisites and assumptions (e.g., "Requires LXC container with standard Ubuntu template")
- Integration points between components (e.g., how secrets flow from 1Password → justfile → Ansible templates)
- References to external documentation (e.g., "Reference: .claude/skills/vmid-allocation.md")

**Block Comments:**
- Use `# ===...===` dividers for major sections in files (80+ character width)
- Use `#` with descriptive text for subsection headers
- Use `#` comment above resource/block explaining its purpose

**Inline Comments:**
- Minimal use (code should be self-documenting)
- Used for "why" not "what" (e.g., "Required for Docker-in-LXC" not "Set nesting to true")

**JSDoc/Docstring:**
- Shell: comments with `Usage:` section in scripts (example: `op-connect.sh` includes full usage in `usage()` function)
- Terraform/Ansible: use `description` fields in variables, outputs, roles
- Just: each recipe includes comment line or multiline description

## Function Design

**Size:** Keep functions focused and under 50 lines where feasible

**Parameters:**
- Terraform: pass via `variable` blocks and locals
- Ansible: use variables from `defaults/main.yaml` and `group_vars/all.yaml`
- Shell: pass as function arguments, validate at function entry
- Just: pass via environment variables or recipe parameters

**Return Values:**
- Terraform: use `output` blocks
- Ansible: use `register` for capturing task output, use handlers for triggered actions
- Shell: use `echo` for output, exit code for status (0=success, 1=error)
- Just: use printf with ANSI colors for formatted output

**Idempotency:**
- Ansible: always design tasks to be idempotent (safe to run multiple times)
- Use `creates` attribute to skip if file exists
- Use `changed_when: false` for read-only tasks
- Use handlers for triggering dependent tasks only on changes
- Terraform: providers and modules handle state management (inherently idempotent)

## Module Design

**Exports:**

**Terraform Modules:**
- Always define `outputs.tf` with clear descriptions
- Export instance details, DNS entries, generated paths (example: `ansible_inventory_path`)
- Use clear naming: `instances`, `dns_entries`, `cname_entries`, `mgmt_ips`

**Ansible Roles:**
- Use `defaults/main.yaml` for all configurable variables
- Use `group_vars/` for group-level overrides
- Use `tasks/main.yaml` as entry point (no other task files needed for single-role services)
- Export via `register` variables accessible after role execution

**Barrel Files:** Not applicable (no JS/TS code in this codebase)

## Domain-Specific Conventions

**Secrets Management:**
- All secrets injected via environment variables from 1Password at deploy time
- Never commit secrets or `.env` files
- Use `op:// ` URI format in justfiles: `op://Vault/Item/Field`
- Secret scripts: `scripts/op-read` wrapper for reading from 1Password
- Ansible: use `no_log: true` for tasks handling secrets

**Infrastructure Identifiers:**
- VMID pattern: 4-digit TSSS format (T=type: 1=LXC, 2=VM; SSS=service/sequence)
  - Example: 1180 = LXC (1) musa-test node josephson octet (.180)
- IP allocation: 192.168.5.x for management network
- Hostname format: `{service}-{env}` (example: `musa-test`)
- DNS: `.lan` for local resolution, `.joeseymour.io` for external

**Docker/Container Conventions:**
- Container names: lowercase with hyphens (e.g., `twenty-swag`, `twenty-backup`)
- Environment variables: UPPER_CASE (e.g., `POSTGRES_USER`, `REDIS_URL`, `CF_ZONE_ID`)
- Health checks: include timeout and retry logic in Compose service definitions
- Logging: use local driver with rotation (max-size: 10m, max-file: 3, compress: true)

**Template Conventions:**
- First line: `# {{ ansible_managed }}` (tells operators file is managed by Ansible)
- Comments: Include description of purpose and what system manages it
- Variable substitution: Use `{{ variable }}` Jinja2 syntax
- Escaping: For multi-line values, use `>-` (chomps trailing newline)
- Defaults: Include sensible defaults in Ansible `defaults/main.yaml`, override via `group_vars/all.yaml` or extra-vars

---

*Convention analysis: 2026-02-28*
