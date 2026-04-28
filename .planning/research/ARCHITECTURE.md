# Architecture Research — Multi-Node HA

## Node Allocation

| Node | Proxmox Host | Role | Services |
|------|-------------|------|----------|
| musa-test-1 | joseph | App + DB + etcd | Twenty server, worker, Patroni (PG), etcd, Redis (master initially), Sentinel, SWAG + cloudflared, pgBackRest |
| musa-test-2 | everette | App + DB + etcd | Twenty server, worker, Patroni (PG), etcd, Redis replica, Sentinel, SWAG + cloudflared |
| musa-test-3 | maxwell | DB + etcd + Backup | Patroni (PG), etcd, Redis replica, Sentinel, pgBackRest repo host, pg_dump GFS cron |

### Why This Layout

- **App on 2 nodes (not 3):** Twenty CRM doesn't need 3 instances. 2 provides failover. Node 3 is DB/backup focused.
- **etcd on all 3:** Quorum requires 3 members. Losing 1 node preserves quorum.
- **Redis Sentinel on all 3:** Quorum requires 3 sentinels.
- **Patroni on all 3:** 1 primary + 2 replicas. Automatic failover to any node.
- **pgBackRest repo on node 3:** Dedicated backup storage, doesn't compete with app workload.
- **cloudflared on nodes 1 + 2:** Where app instances run. Same tunnel token = automatic failover.

## Service Placement Diagram

```text
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  musa-test-1        │  │  musa-test-2        │  │  musa-test-3        │
│  (joseph)           │  │  (everette)         │  │  (maxwell)          │
│                     │  │                     │  │                     │
│  ┌───────────────┐  │  │  ┌───────────────┐  │  │                     │
│  │ SWAG+tunnel   │  │  │  │ SWAG+tunnel   │  │  │                     │
│  │ :80 :443      │  │  │  │ :80 :443      │  │  │                     │
│  └───────┬───────┘  │  │  └───────┬───────┘  │  │                     │
│          │          │  │          │          │  │                     │
│  ┌───────┴───────┐  │  │  ┌───────┴───────┐  │  │                     │
│  │ Twenty server │  │  │  │ Twenty server │  │  │                     │
│  │ Twenty worker │  │  │  │ Twenty worker │  │  │                     │
│  └───────────────┘  │  │  └───────────────┘  │  │                     │
│                     │  │                     │  │                     │
│  ┌───────────────┐  │  │  ┌───────────────┐  │  │  ┌───────────────┐  │
│  │ Patroni (PG)  │  │  │  │ Patroni (PG)  │  │  │  │ Patroni (PG)  │  │
│  │ :5432         │◄─┼──┼──┤ :5432         │◄─┼──┼──┤ :5432         │  │
│  └───────────────┘  │  │  └───────────────┘  │  │  └───────────────┘  │
│                     │  │                     │  │                     │
│  ┌───────────────┐  │  │  ┌───────────────┐  │  │  ┌───────────────┐  │
│  │ etcd          │  │  │  │ etcd          │  │  │  │ etcd          │  │
│  │ :2379 :2380   │◄─┼──┼──┤ :2379 :2380   │◄─┼──┼──┤ :2379 :2380   │  │
│  └───────────────┘  │  │  └───────────────┘  │  │  └───────────────┘  │
│                     │  │                     │  │                     │
│  ┌───────────────┐  │  │  ┌───────────────┐  │  │  ┌───────────────┐  │
│  │ Redis master  │  │  │  │ Redis replica │  │  │  │ Redis replica │  │
│  │ :6379         │◄─┼──┼──┤ :6379         │◄─┼──┼──┤ :6379         │  │
│  │ Sentinel      │  │  │  │ Sentinel      │  │  │  │ Sentinel      │  │
│  │ :26379        │◄─┼──┼──┤ :26379        │◄─┼──┼──┤ :26379        │  │
│  └───────────────┘  │  │  └───────────────┘  │  │  └───────────────┘  │
│                     │  │                     │  │                     │
│  ┌───────────────┐  │  │                     │  │  ┌───────────────┐  │
│  │ pgBackRest    │  │  │                     │  │  │ pgBackRest    │  │
│  │ (local agent) │  │  │                     │  │  │ (repo host)   │  │
│  └───────────────┘  │  │                     │  │  │ pg_dump GFS   │  │
│                     │  │                     │  │  └───────────────┘  │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘
```

## Cross-LXC Networking

### Approach: Direct Host Networking (not Docker overlay)

Each LXC gets a management IP on the 192.168.5.0/24 VLAN. Services that need cross-node communication bind to the LXC's IP (not Docker bridge IPs).

**Why not Docker overlay networks:**
- Docker overlay requires Swarm mode initialization
- Adds complexity (key-value store, encryption, routing mesh)
- LXC-to-LXC networking via Proxmox VLAN is already available and proven

**Implementation:**
- etcd: Use `--listen-peer-urls http://0.0.0.0:2380` and `--advertise-peer-urls http://<lxc-ip>:2380`
- Patroni: Set `connect_address: <lxc-ip>:5432` and `restapi.connect_address: <lxc-ip>:8008`
- Redis Sentinel: Set `sentinel announce-ip <lxc-ip>` and `sentinel announce-port 26379`
- Redis data: Use `replica-announce-ip <lxc-ip>`

**Port mapping:** Docker containers use `network_mode: host` for services requiring cross-node communication, OR use explicit port binding to LXC IP.

### IP Allocation (test environment)

| Node | VMID | IP |
|------|------|-----|
| musa-test-1 | 1180 | 192.168.5.180 (existing) |
| musa-test-2 | 1181 | 192.168.5.181 (new) |
| musa-test-3 | 1182 | 192.168.5.182 (new) |

VMID pattern: 1180–1182 (LXC prefix 1xxx + octet)

## Terraform Changes

### Current (single node)
- 1 LXC module call in `terraform/envs/test/main.tf`
- Single inventory file generated

### New (multi-node)
- 3 LXC module calls (or `for_each` over node map)
- Each LXC on different Proxmox node (joseph, everette, maxwell)
- Node 3 gets larger disk (backup storage)
- Inventory generation: group-based (app_nodes, db_nodes, etcd_nodes, all)
- New outputs: node IPs for cross-references

### Resource Allocation (test)

| Node | Cores | Memory | Disk | Notes |
|------|-------|--------|------|-------|
| musa-test-1 | 4 | 4096 MB | 20G | App + DB |
| musa-test-2 | 4 | 4096 MB | 20G | App + DB |
| musa-test-3 | 2 | 2048 MB | 40G | DB + Backup (larger disk) |

## Ansible Changes

### Current
- Single role `musa` deploying Docker Compose stack
- Single inventory group `musa`

### New
- Multiple inventory groups: `etcd_nodes`, `patroni_nodes`, `app_nodes`, `backup_nodes`
- Deployment order matters:
  1. etcd cluster first (all 3 nodes)
  2. Patroni cluster (all 3 nodes, bootstrap primary first)
  3. Redis + Sentinel (all 3 nodes)
  4. pgBackRest repo host (node 3), then stanza creation
  5. App instances (nodes 1 + 2)
  6. Cloudflare Tunnel (nodes 1 + 2)
- Per-node Docker Compose templates (different services per node role)
- OR: Single compose template with conditional services based on host vars

## Suggested Build Order

### Phase order (dependency-driven)

1. **Multi-node Terraform** — Provision 3 LXCs, generate multi-node inventory
2. **etcd cluster** — Foundation for Patroni; must be running first
3. **Patroni PostgreSQL cluster** — Depends on etcd; Twenty CRM's primary dependency
4. **Data migration** — Migrate existing single-node PG data to Patroni cluster
5. **Redis Sentinel** — Independent of PG; can parallelize with step 4
6. **pgBackRest** — Depends on Patroni cluster being stable
7. **App instances + dual tunnel** — Depends on PG + Redis being HA
8. **Failover validation** — Test each HA component
9. **Production environment** — Same topology, larger resources

### Rationale
- etcd before Patroni: hard dependency
- Patroni before app: app needs working PG
- Redis Sentinel can parallelize with data migration
- pgBackRest after Patroni: needs stable cluster for stanza creation
- Failover validation before production: prove it works on test
