# Stack Research — Multi-Node HA Additions

## Existing Stack (DO NOT change)

- Docker-in-LXC on Proxmox (nesting=true)
- Docker Compose for orchestration inside each LXC
- SWAG (linuxserver/swag) reverse proxy + Let's Encrypt
- cloudflared inside SWAG container
- PostgreSQL (official postgres image)
- Redis (official redis image)
- Ansible + Terraform/OpenTofu pipeline
- 1Password CLI secret injection

## New Stack Additions

### Patroni — PostgreSQL HA

- **Version:** Patroni 4.1.2 (released April 2026)
- **Docker image:** Build custom image based on `postgres:16` + Patroni pip install, OR use `patroni/patroni` official Docker Compose reference
- **Why custom image:** No official Patroni Docker Hub image with guaranteed version pinning. The Patroni repo provides a Dockerfile in their repo that builds on top of official PostgreSQL.
- **PostgreSQL version:** Stay on PostgreSQL 16 (Twenty CRM validated version). Patroni supports PG 9.3–18.
- **Python requirement:** Patroni 4.x requires Python 3.8+
- **Key config:** `loop_wait`, `retry_timeout`, `ttl` tuning critical for Docker environments
- **DCS client:** python-etcd3 (bundled with Patroni)

### etcd — Distributed Consensus Store

- **Version:** etcd v3.5.x (3.5 is current stable; v3.6 in preview)
- **Docker image:** `quay.io/coreos/etcd:v3.5.17` or `bitnami/etcd:3.5`
- **Why etcd over Consul/ZooKeeper:** Patroni's primary DCS, most examples and docs target etcd. Lighter than Consul for single-purpose DCS use.
- **Cluster size:** 3 nodes (one per LXC, maps to 3 Proxmox nodes)
- **Key requirement:** Static bootstrap with `--initial-cluster` listing all 3 members
- **Networking:** Peers communicate on port 2380, clients on 2379. Must use LXC management IPs (not Docker internal IPs)
- **Auth note:** Recent etcd releases require authentication for cluster topology reads and lease keepalive — Patroni 4.1.x handles this

### Redis Sentinel — Redis HA

- **Version:** Redis 7.2.x (current stable)
- **Docker image:** `redis:7.2-alpine` for both data nodes and sentinels
- **Architecture:** 1 master + 2 replicas + 3 sentinels (sentinels can colocate with data nodes)
- **Critical Docker caveat:** Sentinel rewrites its own config file with discovered IPs. In Docker, NAT/port remapping breaks auto-discovery. Must use `host` network mode OR explicitly set `sentinel announce-ip` and `sentinel announce-port`.
- **Minimum sentinels for quorum:** 3 (maps to 3 nodes)

### pgBackRest — Backup & Recovery

- **Version:** pgBackRest 2.54 (current stable)
- **Docker image:** `woblerr/docker-pgbackrest` community image, or bundle into custom Patroni image
- **Key finding:** pgBackRest does NOT natively support GFS (grandfather-father-son) retention. It supports count-based or time-based retention only.
- **Retention strategy:** Use multiple stanzas or scheduled full/diff/incr backups with time-based retention to approximate GFS:
  - Full backup weekly, retain 4 (monthly coverage)
  - Differential daily, retain 7
  - PITR via continuous WAL archiving (repo-retention-archive-type=full)
- **Repo host:** Dedicated pgBackRest repo on one node, or shared storage via Ceph
- **PITR capability:** Continuous WAL archiving to repo, restore to any point in time

### GFS Backup (pg_dump complement)

- **Tool:** Standard `pg_dump` / `pg_dumpall` via cron (existing backup container pattern)
- **Purpose:** Portable logical backups independent of pgBackRest physical backups
- **Retention:** Implement GFS rotation in shell script (hourly/24h, daily/7d, weekly/4w, monthly/12mo)
- **Why both:** pgBackRest for fast PITR recovery; pg_dump for portable cross-version backups

### Cloudflare Tunnel — HA Ingress

- **Version:** cloudflared latest (auto-updates via SWAG container)
- **HA mechanism:** Same tunnel token on multiple hosts = replicas. Cloudflare routes to geographically closest replica, fails over automatically.
- **Limit:** Up to 25 replicas (100 connections) per tunnel
- **No config change needed:** Same tunnel token, same public hostname. Just run cloudflared on both app nodes.
- **NOT load balancing:** Replicas provide failover, not round-robin. For true load balancing, need Cloudflare Load Balancer product (separate).

## What NOT to Add

| Technology | Reason |
|-----------|--------|
| Kubernetes / K3s | Overkill for 3-node homelab; Docker Compose per node is proven |
| Docker Swarm overlay | Adds complexity; direct host networking between LXCs is simpler |
| Consul / ZooKeeper | etcd is Patroni's primary target, less operational overhead |
| Redis Cluster (sharding) | CRM workload doesn't need sharding; Sentinel sufficient |
| HAProxy for PG | Twenty CRM connects to single PG host; Patroni VIP or app-level failover simpler |
| PgBouncer | Not needed at CRM scale; add later if connection pooling becomes issue |
| Citus | Distributed PG unnecessary for CRM workload |

## Version Matrix

| Component | Version | Image |
|-----------|---------|-------|
| Patroni | 4.1.2 | Custom (postgres:16 + patroni) |
| etcd | 3.5.17 | quay.io/coreos/etcd:v3.5.17 |
| Redis | 7.2 | redis:7.2-alpine |
| pgBackRest | 2.54 | Bundled in Patroni image |
| cloudflared | latest | cloudflare/cloudflared |
| PostgreSQL | 16 | Base for Patroni image |
