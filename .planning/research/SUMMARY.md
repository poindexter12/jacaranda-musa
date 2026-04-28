# Research Summary — Multi-Node HA

## Stack Additions

| Component | Version | Image | Purpose |
|-----------|---------|-------|---------|
| Patroni | 4.1.2 | Custom (postgres:16 + patroni pip) | PostgreSQL HA with automatic failover |
| etcd | 3.5.17 | quay.io/coreos/etcd:v3.5.17 | Distributed consensus for Patroni leader election |
| Redis Sentinel | 7.2 | redis:7.2-alpine | Redis HA with automatic master promotion |
| pgBackRest | 2.54 | Bundled in Patroni image | PITR backup with continuous WAL archiving |
| cloudflared | latest | cloudflare/cloudflared | HA ingress via tunnel replicas |

## Key Findings

### pgBackRest Does NOT Support Native GFS
Original plan called for GFS rotation (hourly/daily/weekly/monthly). pgBackRest only supports count-based or time-based retention. **Revised strategy:** pgBackRest for PITR (continuous WAL + scheduled full/diff backups with time-based retention) + standalone pg_dump with shell-scripted GFS rotation for portable logical backups.

### Cloudflare Tunnel HA is Trivially Simple
Same tunnel token on multiple hosts = automatic failover. No config changes, no DNS updates. Cloudflare handles routing. This is the easiest HA component.

### Redis Sentinel + Docker = IP Announcement Pain
Docker NAT breaks Sentinel auto-discovery. Must explicitly set `announce-ip` on all Redis data nodes and sentinels. This is the most common Docker+Sentinel failure mode.

### Patroni + etcd Coupling is Tight
etcd outage → Patroni demotes ALL PostgreSQL nodes (by design, prevents split-brain). etcd cluster health is the single most critical operational concern. Must be deployed and validated first.

### Twenty CRM Needs Sentinel-Aware Redis Config
Default REDIS_URL (host:port) won't failover. Must configure Twenty CRM to use Sentinel discovery. Need to verify Twenty's Node.js Redis client (likely ioredis) supports Sentinel mode.

## Architecture Decision

**3 LXCs across 3 Proxmox nodes:**
- Nodes 1+2: App (Twenty server/worker/SWAG/tunnel) + DB (Patroni/etcd/Redis)
- Node 3: DB + Backup (Patroni/etcd/Redis + pgBackRest repo + pg_dump GFS)
- App on 2 nodes (sufficient for CRM), DB on 3 (quorum for etcd/Sentinel/Patroni)

**Networking:** Direct LXC-to-LXC via management VLAN (192.168.5.x). No Docker overlay/Swarm needed.

## Build Order (dependency-driven)

1. Multi-node Terraform (3 LXCs)
2. etcd cluster (foundation)
3. Patroni PostgreSQL cluster
4. Data migration from single-node
5. Redis Sentinel (can parallelize with #4)
6. pgBackRest PITR
7. Dual app instances + tunnel
8. Failover validation
9. Production environment

## Top Pitfalls to Watch

| # | Pitfall | Severity | When |
|---|---------|----------|------|
| P1 | etcd outage kills all PG nodes | CRITICAL | Phase: etcd + Patroni |
| P4 | PG data volume persistence | CRITICAL | Phase: Patroni |
| P8 | Sentinel Docker IP discovery | CRITICAL | Phase: Redis |
| P11 | pgBackRest stanza timing | HIGH | Phase: Backup |
| P12 | archive_command ownership conflict | HIGH | Phase: Backup |
| P16 | Ansible deployment ordering | HIGH | Phase: All |
| P10 | Twenty CRM Sentinel client config | HIGH | Phase: App |

## What NOT to Do

- Don't use Docker Swarm overlay networking — direct VLAN is simpler
- Don't use Consul/ZooKeeper — etcd is Patroni's primary target
- Don't use Redis Cluster — Sentinel is sufficient for CRM workload
- Don't use HAProxy for PG — Patroni handles failover, app reconnects
- Don't try native GFS in pgBackRest — it doesn't support it
- Don't update multiple cluster nodes simultaneously — always rolling

## Sources

- [Patroni GitHub](https://github.com/patroni/patroni) — v4.1.2, Docker Compose reference
- [Patroni Release Notes](https://patroni.readthedocs.io/en/latest/releases.html) — v4.1.2
- [etcd Container Guide](https://etcd.io/docs/v3.4/op-guide/container/)
- [Redis Sentinel Docs](https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/)
- [Cloudflare Tunnel Availability](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/tunnel-availability/)
- [pgBackRest User Guide](https://pgbackrest.org/user-guide.html)
- [pgBackRest Configuration Reference](https://pgbackrest.org/configuration.html)
- [pgBackRest GFS Feature Request](https://github.com/pgbackrest/pgbackrest/issues/1972) — confirms no native GFS
- [Data Egret — pgBackRest PITR in Docker](https://dataegret.com/2025/12/pgbackrest-pitr-in-docker-a-simple-demo/)
- [Patroni Troubleshooting](https://bootvar.com/patroni-troubleshooting/)
