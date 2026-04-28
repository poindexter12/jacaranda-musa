# Pitfalls Research — Multi-Node HA

## Patroni in Docker Compose

### P1: DCS Connection Loss = PostgreSQL Shutdown
- **Severity:** CRITICAL
- **Description:** If Patroni loses connection to etcd for longer than `ttl` (default 30s), it demotes the primary to prevent split-brain. This is by design but surprising — an etcd outage takes down ALL PostgreSQL nodes.
- **Prevention:** Ensure etcd cluster is rock-solid. Set reasonable `ttl`/`loop_wait`/`retry_timeout` values. Consider: etcd on 3 nodes means losing 2 etcd nodes = total PG outage.
- **Detection:** Monitor Patroni REST API (:8008/patroni) and etcd health endpoints.

### P2: Bootstrap vs Failover Confusion
- **Severity:** HIGH
- **Description:** Patroni has different behavior for initial cluster bootstrap vs. failover. First node must initialize PG data directory; subsequent nodes clone from primary. If config is wrong, all 3 nodes try to bootstrap independently = 3 separate databases.
- **Prevention:** Use `bootstrap.dcs` config carefully. Set `bootstrap.initdb` only for first-time setup. Use `--scope` consistently across all nodes.
- **Detection:** Check `patronictl list` — all nodes should show same cluster name and one leader.

### P3: Docker Restart Policies vs Patroni Lifecycle
- **Severity:** HIGH
- **Description:** Docker `restart: always` can conflict with Patroni's own restart logic. Patroni manages PG process lifecycle; Docker restarting the container on PG crash can race with Patroni's recovery.
- **Prevention:** Use `restart: unless-stopped`. Let Patroni handle PG restarts internally. Docker only restarts on container-level crashes.
- **Detection:** Check for rapid restart loops in `docker logs`.

### P4: Data Directory Persistence
- **Severity:** CRITICAL
- **Description:** PostgreSQL data directory must survive container restarts. If Docker volume is misconfigured, PG data is lost on container restart, and Patroni tries to re-bootstrap from scratch.
- **Prevention:** Named Docker volumes or bind mounts for `/var/lib/postgresql/data`. Never use anonymous volumes.
- **Detection:** Verify volume mounts in compose file. Test with `docker compose down && docker compose up`.

## etcd Cluster in Docker

### P5: Quorum Loss on Single Node Failure
- **Severity:** HIGH
- **Description:** 3-node etcd cluster tolerates exactly 1 node failure. If 2 nodes go down (e.g., during rolling update), etcd loses quorum and becomes read-only. This cascades to Patroni (see P1).
- **Prevention:** Never update more than 1 etcd node at a time. Use Ansible `serial: 1` for etcd updates.
- **Detection:** `etcdctl endpoint health` on all nodes before operations.

### P6: etcd Data Directory Corruption
- **Severity:** HIGH
- **Description:** etcd stores state in a WAL directory. Improper shutdown (kill -9, power loss) can corrupt it. Corrupt member can't rejoin cluster.
- **Prevention:** Named volumes for etcd data. Graceful shutdown via `docker compose stop`. Regular etcd snapshots.
- **Detection:** etcd logs showing "wal" errors or "snap" corruption messages.

### P7: Clock Skew Between Nodes
- **Severity:** MEDIUM
- **Description:** etcd uses lease TTLs sensitive to time. Significant clock skew between LXC containers can cause spurious leader elections.
- **Prevention:** Ensure NTP is running on all Proxmox hosts. LXC containers inherit host time.
- **Detection:** Compare `date` across nodes; check etcd logs for "lease expired" messages.

## Redis Sentinel in Docker

### P8: Sentinel Config Rewriting with Docker IPs
- **Severity:** CRITICAL
- **Description:** Redis Sentinel rewrites its own config file with discovered IP addresses. In Docker, it discovers the container's internal IP (172.x.x.x) instead of the LXC IP. Other nodes' sentinels can't reach these IPs.
- **Prevention:** MUST set `sentinel announce-ip` and `sentinel announce-port` to LXC management IPs. Also set `replica-announce-ip` on Redis data nodes.
- **Detection:** `redis-cli -p 26379 SENTINEL master mymaster` — check announced IPs match LXC IPs.

### P9: Sentinel Quorum During Rolling Updates
- **Severity:** MEDIUM
- **Description:** Restarting sentinel nodes during updates can temporarily drop quorum. If master fails during this window, no failover occurs.
- **Prevention:** Restart sentinels one at a time with verification between each. Never restart all sentinels simultaneously.
- **Detection:** `redis-cli -p 26379 SENTINEL ckquorum mymaster` before and after each restart.

### P10: Twenty CRM Redis Client Configuration
- **Severity:** HIGH
- **Description:** Twenty CRM's REDIS_URL must support Sentinel-based master discovery. If it only supports direct host:port, Sentinel failover won't be transparent to the app.
- **Prevention:** Research Twenty CRM's Redis client library (likely ioredis for Node.js). ioredis supports Sentinel natively. Configure with Sentinel addresses instead of direct Redis host.
- **Detection:** Check Twenty's .env / environment variable support for Sentinel mode.

## pgBackRest with Patroni

### P11: Stanza Creation Timing
- **Severity:** HIGH
- **Description:** pgBackRest stanza must be created AFTER Patroni bootstraps the primary. If created before PG data exists, stanza creation fails. If archive_command is set before stanza exists, WAL archiving fails.
- **Prevention:** Ansible deployment order: Patroni bootstrap → wait for healthy primary → create pgBackRest stanza → enable WAL archiving in Patroni config.
- **Detection:** pgBackRest `stanza-check` returns errors if stanza or repo is misconfigured.

### P12: archive_command Ownership
- **Severity:** HIGH
- **Description:** Both Patroni and pgBackRest want to control `archive_command`. Patroni sets it via DCS config; pgBackRest needs it to point to `pgbackrest archive-push`. If Patroni overrides it, WAL archiving breaks.
- **Prevention:** Set `archive_command` in Patroni's `bootstrap.dcs.postgresql.parameters` section, pointing to pgBackRest. Don't set it in postgresql.conf directly.
- **Detection:** `patronictl show-config` — verify archive_command value.

### P13: Backup from Standby Configuration
- **Severity:** MEDIUM
- **Description:** Taking backups from standby reduces primary load but requires pgBackRest to know which node is primary vs standby. Patroni role changes mean the backup source can change.
- **Prevention:** Configure pgBackRest with all PG hosts; use `backup-standby=y` option. pgBackRest auto-detects primary/standby roles.
- **Detection:** Check pgBackRest backup logs for "backup from standby" confirmation.

## Docker Networking Across LXCs

### P14: Port Conflicts with Host Network Mode
- **Severity:** MEDIUM
- **Description:** Using `network_mode: host` means all containers share the LXC's network namespace. Port conflicts between services (e.g., two services wanting port 8080).
- **Prevention:** Careful port allocation per service. Alternatively, use Docker bridge network with explicit port binds to LXC IP (`ports: ["192.168.5.180:5432:5432"]`).
- **Detection:** `docker compose up` fails with "address already in use".

### P15: DNS Resolution Between LXCs
- **Severity:** LOW
- **Description:** Docker containers can't resolve other LXCs by hostname (musa-test-1.lan) unless DNS is configured. Using IPs directly is fragile.
- **Prevention:** Use Ansible templates with IP variables from Terraform outputs. Pi-hole handles .lan resolution for LXC hostnames.
- **Detection:** `dig musa-test-2.lan` from inside container.

## Ansible Multi-Node Management

### P16: Deployment Order Dependencies
- **Severity:** HIGH
- **Description:** Services must start in dependency order across nodes: etcd → Patroni → Redis → App. Ansible's default parallel execution doesn't respect cross-host ordering.
- **Prevention:** Use separate plays per service layer with `hosts: etcd_nodes`, `hosts: patroni_nodes`, etc. Or use `serial: 1` with explicit ordering.
- **Detection:** Service startup failures in Ansible output due to missing dependencies.

### P17: Rolling Updates Without Downtime
- **Severity:** MEDIUM
- **Description:** Updating all nodes simultaneously breaks HA. Need rolling strategy: update one node, verify health, proceed to next.
- **Prevention:** Ansible `serial: 1` for update playbooks. Health check verification between nodes. Never update more than minority of cluster simultaneously.
- **Detection:** Service downtime during deploys.

## Terraform Multi-LXC

### P18: State Management for Multiple LXCs
- **Severity:** MEDIUM
- **Description:** Single terraform state file for all 3 LXCs means any change risks all nodes. Terraform plan affects entire environment.
- **Prevention:** Accept single state (3 LXCs is small). Use `for_each` or separate module calls with explicit targeting. Consider `terraform apply -target` for emergency single-node changes.
- **Detection:** Review terraform plan carefully before apply.
