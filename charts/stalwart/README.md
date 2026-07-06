# stalwart

Deploys [Stalwart Mail Server](https://stalw.art/) as a StatefulSet with persistent storage and standard mail listeners.

## Values

| Key | Default | Notes |
| --- | --- | --- |
| `image.repository` | `stalwartlabs/stalwart` | Container image |
| `image.tag` | chart `appVersion` | Pin for controlled upgrades |
| `replicaCount` | `1` | Keep at `1` for local RocksDB |
| `recoveryAdmin.enabled` | `false` | Enable for first bootstrap only |
| `recoveryAdmin.existingSecret` | `""` | Pre-created Secret for recovery admin credentials |
| `recoveryAdmin.usernameKey` | `username` | Secret key for recovery admin username |
| `recoveryAdmin.passwordKey` | `password` | Secret key for recovery admin password |
| `bootstrap.enabled` | `false` | Run hook Job to provision domain, accounts, and OIDC directory |
| `bootstrap.domain` | `""` | Mail domain name for bootstrap |
| `bootstrap.oidc.issuerUrl` | `""` | OIDC provider issuer URL |
| `config` | RocksDB data store | Only DataStore belongs in `config.json` |
| `service.type` | `ClusterIP` | Main Service; use with ingress for management UI |
| `mailService.enabled` | `false` | Separate LoadBalancer for SMTP/IMAP/POP3/Sieve |
| `mailService.name` | `""` | Optional Service name (e.g. `stalwart-mail`) when adopting a hand-maintained LoadBalancer |
| `mailService.annotations` | `{}` | e.g. MetalLB `metallb.universe.tf/loadBalancerIPs` |
| `ingress.enabled` | `false` | HTTP/S management only |
| `persistence.enabled` | `true` | Disable for external DataStore backends |
| `resources` | `{}` | Set CPU/memory requests and limits per environment |
| `podSecurityContext` | non-root, `RuntimeDefault` seccomp | Runs as UID/GID 2000 |
| `containerSecurityContext` | drops all caps, keeps `NET_BIND_SERVICE` | Needed for privileged mail ports |
| `envFrom` | `[]` | Optional extra `envFrom` entries (e.g. DB password secrets) |
| `affinity` | `{}` | Optional pod affinity/anti-affinity |
| `topologySpreadConstraints` | `[]` | Optional topology spread |
| `podDisruptionBudget.enabled` | `false` | Enable PDB for multi-replica installs |
| `metrics.serviceMonitor.enabled` | `false` | Prometheus Operator ServiceMonitor |

`bootstrap` provisions domain, accounts, and an external OIDC directory. Register the IdP app and Secrets outside the chart. Set `STALWART_PUBLIC_URL` and route ingress to `mgmt` for WebUI login.

See [values.yaml](values.yaml) and the [Stalwart Kubernetes docs](https://stalw.art/docs/cluster/orchestration/kubernetes/) for clustering and external stores.

## Upgrading from 0.7.x to 0.8.x

### Breaking changes

Chart **0.8.x** adds optional HA-related values (`envFrom`, `affinity`, `topologySpreadConstraints`, `podDisruptionBudget`, `metrics.serviceMonitor`). **Defaults are unchanged** — a straight `helm upgrade` on a single-replica RocksDB install needs no config changes.

You only need the steps below if you are moving to a **shared DataStore** (PostgreSQL, FoundationDB, etc.) for multi-replica HA. That is a **one-time data migration**, not a chart toggle. See Stalwart’s [data store](https://stalw.art/docs/storage/data/) and [migration](https://stalw.art/docs/management/maintenance/migration/) docs for background.

| Key | Default | When enabling HA |
| --- | --- | --- |
| `envFrom` | `[]` | Mount secrets (e.g. `STALWART_DB_PASSWORD`) |
| `affinity` / `topologySpreadConstraints` | empty | Spread pods across nodes |
| `podDisruptionBudget.enabled` | `false` | `true` with multiple replicas |
| `metrics.serviceMonitor.enabled` | `false` | Prometheus Operator scrape |

### RocksDB → PostgreSQL migration (one-off)

Use the script in this repo — it creates short-lived Kubernetes Jobs to export from your existing RocksDB PVC and import into PostgreSQL. See [scripts/migrate-rocksdb-to-postgres.sh](../../scripts/migrate-rocksdb-to-postgres.sh).

**Before you start**

1. Provision PostgreSQL and a database user; create a Secret with `STALWART_DB_PASSWORD` (e.g. `stalwart-db`).
2. Snapshot the RocksDB PVC (or take a Longhorn volume snapshot).
3. Scale Stalwart to zero so RocksDB is not mounted read-write:

   ```bash
   kubectl scale statefulset/stalwart-stalwart -n stalwart --replicas=0
   kubectl wait -n stalwart --for=delete pod -l app.kubernetes.io/name=stalwart --timeout=300s
   ```

**Run migration**

Adjust environment variables if your namespace, PVC name, Postgres service, or secret differ from the defaults (`./scripts/migrate-rocksdb-to-postgres.sh --help`).

```bash
chmod +x scripts/migrate-rocksdb-to-postgres.sh

export NAMESPACE=stalwart
export DATA_CLAIM=data-stalwart-stalwart-0   # RocksDB PVC from the StatefulSet
export DB_SECRET_NAME=stalwart-db
export POSTGRES_HOST=postgres-rw.postgres.svc.cluster.local
export POSTGRES_DATABASE=stalwart
export POSTGRES_USER=stalwart

./scripts/migrate-rocksdb-to-postgres.sh all
```

`all` runs export, then import, and prints Job logs. On failure, fix the issue and re-run the failed phase (`export` or `import` only).

**After migration**

1. Upgrade Helm values to PostgreSQL and disable local persistence:

   ```yaml
   replicaCount: 1
   config:
     "@type": PostgreSql
     host: postgres-rw.postgres.svc.cluster.local
     port: 5432
     database: stalwart
     authUsername: stalwart
     authSecret:
       "@type": EnvironmentVariable
       variableName: STALWART_DB_PASSWORD
   persistence:
     enabled: false
   envFrom:
     - secretRef:
         name: stalwart-db
   ```

2. `helm upgrade` (or apply your GitOps manifest) and confirm mail, IMAP, and the admin UI.
3. In the Stalwart WebUI, configure a **Coordinator** (peer-to-peer is fine to start).
4. Scale to multiple replicas and enable guardrails:

   ```yaml
   replicaCount: 2
   podDisruptionBudget:
     enabled: true
     minAvailable: 1
   affinity:
     podAntiAffinity:
       preferredDuringSchedulingIgnoredDuringExecution:
         - weight: 100
           podAffinityTerm:
             labelSelector:
               matchLabels:
                 app.kubernetes.io/name: stalwart
             topologyKey: kubernetes.io/hostname
   metrics:
     serviceMonitor:
       enabled: true
       labels:
         release: prometheus
   ```

5. Remove migration scratch resources:

   ```bash
   ./scripts/migrate-rocksdb-to-postgres.sh cleanup
   ```
