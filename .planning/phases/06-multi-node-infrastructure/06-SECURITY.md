---
phase: 06
slug: multi-node-infrastructure
status: verified
threats_open: 0
asvs_level: 1
created: 2026-04-28
---

# Phase 06 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Proxmox API | Terraform authenticates via API token from base-infra | API token (secret), LXC config (non-secret) |
| SSH to LXC | Operator workstation SSH to LXC containers as root | Commands, config files, secrets via extra-vars |
| Transfer VLAN | Cross-node cluster traffic on 192.168.11.x | Future: etcd, PG replication, Redis sentinel (internal only) |
| Multi-host iteration | Justfile recipes loop over hosts array via SSH | SSH sessions to .lan hostnames |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-06-01 | S (Spoofing) | Transfer VLAN traffic | accept | VLAN isolation, no internet exposure. TLS deferred to later phases. | closed |
| T-06-02 | T (Tampering) | Ansible inventory file | mitigate | `file_permission = "0644"` in `local_file.ansible_inventory`, git-tracked, header warns "do not edit manually" | closed |
| T-06-03 | I (Info Disclosure) | Terraform state | accept | Only IPs/VMIDs (non-secret). State encryption via opentofu passphrase. | closed |
| T-06-04 | D (DoS) | LXC resource allocation | mitigate | Per-instance limits via `bak_cores`/`bak_memory`/`bak_disk_size` locals with `coalesce`. Backup node capped at 2c/2048M. | closed |
| T-06-05 | E (Elevation) | Docker nesting | accept | `nesting=true` required for Docker-in-LXC. Established v1.17 pattern. Proxmox unprivileged containers limit blast radius. | closed |
| T-06-06 | S (Spoofing) | SSH host verification | mitigate | LXC module signs host certificates via SSH CA (`ssh_user_ca_pubkey`). Operator workstation trusts CA. 20 SSH CA references in LXC module. | closed |
| T-06-07 | T (Tampering) | Rollback snapshots | accept | `.bak` files stored on each LXC at `/opt/musa/`. Root-only access. Low risk for test environment. | closed |
| T-06-08 | I (Info Disclosure) | Justfile secrets | mitigate | Secrets passed via `op-read` script as Ansible extra-vars. Never logged to stdout. Ansible tasks use `no_log`. | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-06-01 | T-06-01 | Transfer VLAN is internal-only (192.168.11.x), no internet exposure. TLS for cluster services deferred to Phases 7-8 where Patroni/etcd/Redis actually use the VLAN. | plan author | 2026-04-28 |
| AR-06-02 | T-06-03 | Terraform state contains only IP addresses and VMIDs — non-secret infrastructure metadata. State encryption via opentofu passphrase provides defense-in-depth. | plan author | 2026-04-28 |
| AR-06-03 | T-06-05 | Docker nesting (`nesting=true`) is architecturally required for Docker-in-LXC pattern established in v1.17. Proxmox unprivileged containers bound the blast radius. | plan author | 2026-04-28 |
| AR-06-04 | T-06-07 | Rollback `.bak` files are root-owned on test LXCs. Compromise of test environment rollback files is low-impact. | plan author | 2026-04-28 |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-04-28 | 8 | 8 | 0 | gsd-secure-phase (inline after auditor timeout) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-04-28
