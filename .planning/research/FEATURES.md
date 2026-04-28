# Features Research — Multi-Node HA

## PostgreSQL HA (Patroni + etcd)

### Table Stakes (must-have)
- Automatic leader election via etcd consensus
- Automatic failover when primary dies (< 30s detection)
- Streaming replication to 2 standby nodes
- Patroni REST API for health checks and manual operations
- Bootstrap: initialize cluster from scratch or from existing PG data
- Reinitialize: rebuild failed replica from current primary

### Differentiators (nice-to-have)
- Synchronous replication mode (zero data loss, higher latency)
- Switchover (planned, graceful primary change)
- Patroni watchdog integration (hardware watchdog for fencing)
- Custom bootstrap methods (pg_basebackup, pgBackRest restore)
- Scheduled maintenance windows (prevent failover during known ops)
- Read-only endpoint for standby queries

### Anti-features (avoid for now)
- Cascading replication (complexity, not needed at 3-node scale)
- Multi-DC async replication (single Proxmox cluster)
- Patroni Raft mode (built-in DCS without etcd — less battle-tested)

### Complexity: HIGH
- etcd cluster must be healthy for any PG operations
- Patroni config YAML per node with node-specific values
- Custom Docker image build pipeline needed
- Cross-node networking for replication + etcd

### Dependencies
- etcd cluster must be running before Patroni starts
- pgBackRest stanza creation after Patroni bootstrap

---

## Redis HA (Sentinel)

### Table Stakes
- Automatic failover: sentinel promotes replica to master
- Client notification: sentinel provides master address to clients
- Quorum-based decision (3 sentinels, quorum=2)
- Replication: 1 master + 2 replicas across nodes

### Differentiators
- Sentinel notification scripts (alert on failover)
- Configurable failover timeout
- Priority-based replica selection

### Anti-features
- Redis Cluster (sharding) — overkill for CRM cache workload
- Redis persistence (RDB/AOF) on replicas — master only sufficient for cache
- TLS between nodes — internal network, unnecessary complexity

### Complexity: MEDIUM
- Sentinel config rewriting is Docker's biggest pain point
- Must use `announce-ip` / `announce-port` in Docker
- Twenty CRM needs Sentinel-aware Redis client config (REDIS_URL with sentinel support)

### Dependencies
- None (independent of PostgreSQL HA)
- Twenty CRM server/worker config must point to Sentinel for master discovery

---

## Ingress HA (Dual Cloudflare Tunnel)

### Table Stakes
- Same tunnel token on 2 app nodes = automatic failover
- Cloudflare routes to nearest healthy replica
- Zero-downtime tunnel connector updates
- No DNS changes needed during failover

### Differentiators
- Cloudflare Load Balancer integration (true traffic distribution)
- Health check configuration in Cloudflare dashboard

### Anti-features
- Multiple separate tunnels (one per node) — complicates DNS
- Cloudflare Load Balancer product (cost, unnecessary for failover-only)

### Complexity: LOW
- Just run cloudflared with same token on both app nodes
- SWAG on each app node handles local nginx

### Dependencies
- Requires Twenty CRM running on 2 nodes
- SWAG container on each app node

---

## Backup & Recovery (pgBackRest + pg_dump GFS)

### Table Stakes
- Continuous WAL archiving (PITR to any second)
- Full backups (weekly)
- Differential backups (daily)
- Backup verification (pgBackRest check)
- Restore to point-in-time
- Restore to specific backup

### Differentiators
- Parallel backup/restore (pgBackRest supports multi-process)
- Backup from standby (reduce primary load)
- Compression (lz4/zstd for speed vs size)
- Remote repo host (dedicated backup storage)
- pg_dump GFS rotation for portable logical backups

### Anti-features
- Barman (less community support for Docker environments)
- WAL-G (simpler but less feature-rich than pgBackRest)
- S3/cloud backup (homelab, local storage preferred)

### Complexity: MEDIUM-HIGH
- pgBackRest + Patroni integration requires careful stanza timing
- WAL archiving config must coordinate with Patroni's archive_command
- Repo host needs SSH or pgBackRest protocol access from all PG nodes
- GFS rotation for pg_dump is separate shell scripting

### Dependencies
- Patroni must be bootstrapped before pgBackRest stanza creation
- Backup repo storage must be accessible from all PG nodes

---

## Operator Experience During Failover

### PostgreSQL Failover (automatic)
1. Primary node dies or becomes unreachable
2. etcd leader lock expires (TTL, typically 30s)
3. Patroni on replicas detect expired lock
4. Replica with most recent WAL wins election
5. New primary promoted, etcd updated
6. Other replicas redirect replication to new primary
7. **App impact:** Connections to old primary fail, reconnect to new primary. Brief outage (30-60s).

### Redis Failover (automatic)
1. Master becomes unreachable
2. Sentinels detect failure (after `down-after-milliseconds`, typically 5-30s)
3. Quorum agrees master is down
4. Sentinel promotes best replica
5. Other sentinels and replicas update
6. **App impact:** Sentinel-aware clients auto-discover new master. Brief pause (5-15s).

### Ingress Failover (automatic)
1. App node dies, cloudflared connection drops
2. Cloudflare detects lost connections
3. Traffic routes to remaining healthy replica
4. **App impact:** In-flight requests may fail, subsequent requests route to healthy node. Near-instant.
