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
| `bootstrap.enabled` | `false` | Hook Job for domain, accounts, OIDC |
| `bootstrap.domain` | `""` | Mail domain name for bootstrap |
| `bootstrap.oidc.issuerUrl` | `""` | OIDC provider issuer URL |
| `config` | RocksDB data store | Only DataStore belongs in `config.json` |
| `valkey.enabled` | `false` | Optional Valkey dependency for coordination + in-memory |
| `inMemoryStore` | `{}` | Redis in-memory singleton (`stalwart-cli apply` when set) |
| `coordinator` | `{}` | Coordinator singleton (`stalwart-cli apply` when set) |
| `apply.image` | `stalwartlabs/cli:1.0.13` | Pinned official CLI |
| `apply.kubectlImage` | `alpine/kubectl:1.37.1` | Rollout / migrate prepare |
| `migration.enabled` | `false` | One-shot RocksDB PVC → shared store (not 0.16→1.0) |
| `migration.dataClaim` | `""` | Required when migrating (e.g. `data-…-0`) |
| `v1Migrate.enabled` | `false` | One-shot 0.16 → 1.0 via `stalwart-migrate` |
| `v1Migrate.alreadyDone` | `false` | Escape hatch when the store is already on 1.0 |
| `v1Migrate.sourceConfig` | `{}` | Live 0.16 DataStore (`config` is the empty 1.0 target) |
| `service.type` | `ClusterIP` | Main Service (use ingress for the management UI) |
| `mailService.enabled` | `false` | Separate LoadBalancer for mail ports |
| `mailService.name` | `""` | Optional fixed Service name |
| `mailService.annotations` | `{}` | LoadBalancer annotations (IP pools, etc.) |
| `ingress.enabled` | `false` | HTTP/S management only |
| `persistence.enabled` | `true` | Disable for external DataStore |
| `resources` | `{}` | Requests/limits per environment |
| `podSecurityContext` | non-root, `RuntimeDefault` | UID/GID 2000 |
| `containerSecurityContext` | drop all, `NET_BIND_SERVICE` | Privileged mail ports |
| `envFrom` | `[]` | e.g. DB password Secret |
| `affinity` | `{}` | Optional |
| `topologySpreadConstraints` | `[]` | Optional |
| `podDisruptionBudget.enabled` | `false` | Multi-replica PDB |
| `metrics.serviceMonitor.enabled` | `false` | Prometheus Operator |

`bootstrap` creates the domain, accounts, and OIDC directory. You still register the IdP and Secrets yourself. Set `STALWART_PUBLIC_URL` and point ingress at the `mgmt` port.

Full knobs: [values.yaml](values.yaml). Upstream K8s notes: [Stalwart docs](https://stalw.art/docs/cluster/orchestration/kubernetes/).

## Upgrade to Stalwart 1.0

Chart 1.0.0 is the breaking major for the refuse-closed cutover.

Chart **1.0.0** is the first release that refuse-closes upgrades without `v1Migrate` / `alreadyDone` / the marker. Treat it as a breaking chart major.

Stalwart 1.0 cannot open a 0.16 data store. Helm upgrades refuse to render until you either run `v1Migrate`, set `v1Migrate.alreadyDone=true` (store already on 1.0), or the `*-v1-migrated` ConfigMap exists. Fresh installs write that marker automatically. `v1Migrate.enabled` is upgrade-only.

1. Create a **new empty** database (same Postgres is fine, new database name).
2. One Helm upgrade: point `config` at the empty target, set `v1Migrate.sourceConfig` to the live 0.16 store, enable `v1Migrate`, keep Valkey/coordinator as today.
3. Wait for `*-migrate-prepare` (removes PDBs, scales mail to 0), then `*-v1-migrate`, then `*-v1-mark`. Mail comes back on 1.0. Do not run a second helm upgrade while that is in flight.
4. Set `v1Migrate.enabled: false` on the next upgrade (marker keeps the Job from re-running).

```yaml
config:
  "@type": PostgreSql
  host: postgres-rw.postgres.svc.cluster.local
  port: 5432
  database: stalwart_v1   # empty target
  authUsername: stalwart
  authSecret:
    "@type": EnvironmentVariable
    variableName: STALWART_DB_PASSWORD
v1Migrate:
  enabled: true
  sourceConfig:
    "@type": PostgreSql
    host: postgres-rw.postgres.svc.cluster.local
    port: 5432
    database: stalwart    # live 0.16 store
    authUsername: stalwart
    authSecret:
      "@type": EnvironmentVariable
      variableName: STALWART_DB_PASSWORD
```

Default `answers.toml` covers main data categories, recommended defaults, blob reuse, proxy client IP (`xForwardedFor`), Redis in-memory from Valkey/`inMemoryStore`, and OAuth registration accept. If `prepare` still asks about an OIDC directory id, append those stanzas to `v1Migrate.answers` and retry.

`migration.enabled` remains RocksDB PVC → shared store only. It is not the 0.16→1.0 path.

## Clustering

`config.json` holds only the data store. This chart does not install Postgres. Put the DB password in a Secret and mount it with `envFrom`.

Two or more replicas need a Redis-family **in-memory store** and a **coordinator**. Easiest: `valkey.enabled: true` (the apply hook sets both `InMemoryStore` and `Coordinator` to that Service). Otherwise set `inMemoryStore` to Redis/Valkey, and `coordinator` to Redis, Valkey, NATS, or Kafka ([apply docs](https://stalw.art/docs/management/cli/apply/), [in-memory store](https://stalw.art/docs/storage/in-memory/)). NATS/Kafka alone is not enough in 1.0.

On install or upgrade, a hook waits for in-cluster `/healthz/ready` and runs `stalwart-cli apply`. It restarts the StatefulSet only when the plan file hash is new, and writes that hash to the annotation `stalwart.io/coordinator-plan-hash`. If the plan did not change, pods stay up.

For `replicaCount > 1` you must set `persistence.enabled=false`, enable Valkey or set `inMemoryStore` + `coordinator`, and give the apply Job recovery-admin credentials.

```yaml
replicaCount: 2
recoveryAdmin:
  existingSecret: stalwart-recovery-admin
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
valkey:
  enabled: true
podDisruptionBudget:
  enabled: true
```

## Upgrade from one replica to HA

Use this when you already run one pod on local RocksDB and want Postgres, Valkey, and two pods.

### 1. Prepare

- Stand up Postgres and a Secret the pods can read (`envFrom`).
- Create a recovery-admin Secret. Set `recoveryAdmin.existingSecret` to its name.
- Snapshot the data PVC. Note the claim name (usually `data-<release>-stalwart-0`).

### 2. Move off RocksDB (still one pod)

Run one Helm upgrade. That turns on the shared store and Valkey, and runs migration once. Keep `replicaCount: 1` for this step.

```yaml
replicaCount: 1
persistence:
  enabled: false
config:
  "@type": PostgreSql
  host: postgres-rw.postgres.svc.cluster.local
  port: 5432
  database: stalwart
  authUsername: stalwart
  authSecret:
    "@type": EnvironmentVariable
    variableName: STALWART_DB_PASSWORD
envFrom:
  - secretRef:
      name: stalwart-db
valkey:
  enabled: true
recoveryAdmin:
  existingSecret: stalwart-recovery-admin
migration:
  enabled: true
  dataClaim: data-RELEASE-stalwart-0   # your real PVC name
```

Wait for the migrate Job to finish and for the `*-migrated` ConfigMap to show up ([migration docs](https://stalw.art/docs/management/maintenance/migration/)). Send a test message and make sure mail still works.

### 3. Scale to two pods

Second Helm upgrade. Disable migration, set two replicas, turn on the PDB.

```yaml
migration:
  enabled: false
replicaCount: 2
podDisruptionBudget:
  enabled: true
```

Add pod anti-affinity if you want the replicas on different nodes.

If `mailService` is a LoadBalancer, set `mailService.externalTrafficPolicy: Local` so traffic lands on nodes that run mail pods. With `Cluster`, some L2 or node-proxy setups send clients to a node with no ready pod and IMAP or SMTP fails.

### 4. Afterward

Keep `migration.enabled: false`. Later chart upgrades should leave mail pods running unless you change the coordinator plan.
