---
created: 2026-03-01T18:15:09.085Z
title: Revisit Ansible variable strategy for long-term
area: ansible
resolves_phase: 6
files:
  - ansible/inventory/group_vars/all.yaml
  - ansible/roles/musa/defaults/main.yaml
---

## Problem

During Phase 05 execution, plan 05-03 consolidated domain variables (`twenty_domain`, `swag_url`, `swag_subdomain`, `twenty_tag`) from role defaults into `group_vars/all.yaml`. This immediately broke deploys because `group_vars/` was at `ansible/group_vars/` — a path Ansible doesn't search (it looks relative to inventory or playbook files).

The quick fix was moving `group_vars/` into `ansible/inventory/group_vars/`. This works but the overall variable strategy feels ad-hoc:

- **Role defaults** (`defaults/main.yaml`): always loaded, simple, but mixes role-level concerns with environment config
- **group_vars** (`inventory/group_vars/all.yaml`): Ansible-standard for environment config, but requires correct directory placement and is less obvious
- **Extra-vars** (justfile `-e` flags): used for secrets only, highest precedence

The current split (role defaults for fallback values + image tags, group_vars for domain/environment config) works for a single test environment but needs to scale to prod.

## Solution

Decide on a long-term pattern. Consider:

1. **All non-secret config in group_vars** (current approach) — standard Ansible, good for multi-env, but requires understanding Ansible variable precedence and directory conventions
2. **All non-secret config in role defaults** (pre-05-03 approach) — simpler, always works, but doesn't naturally separate per-environment overrides
3. **Group-specific vars** (e.g., `group_vars/musa.yaml` instead of `all.yaml`) — more targeted, scales better if inventory grows
4. **Standardize in jacaranda-shared-libs** — establish a convention that all jacaranda services follow for Ansible variable placement

Also consider whether the shared `ansible.just` recipe should document or enforce the expected `group_vars` location.
