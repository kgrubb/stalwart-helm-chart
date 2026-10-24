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
| `valkey.enabled` | `false` | Optional Valkey dependency for coordination |
| `coordinator` | `{}` | Coordinator singleton (`stalwart-cli apply` when set) |
| `apply.image` | `stalwartlabs/cli:1.0.13` | Pinned official CLI |
| `apply.kubectlImage` | `alpine/kubectl:1.37.1` | Rollout / migrate prepare |
| `apply.rolloutRestart` | `true` | Bounce STS after coordinator apply (set `false` once HA is live) |
| `migration.enabled` | `false` | One-shot RocksDB PVC → shared store |
| `migration.dataClaim` | `""` | Required when migrating (e.g. `data-…-0`) |
| `service.type` | `ClusterIP` | Main Service; ingress for management UI |
| `mailService.enabled` | `false` | Separate LoadBalancer for mail ports |
| `mailService.name` | `""` | Optional fixed Service name |
| `mailService.annotations` | `{}` | e.g. MetalLB annotations |
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

`bootstrap` provisions domain, accounts, and OIDC. Register the IdP and Secrets outside the chart. Set `STALWART_PUBLIC_URL` and route ingress to `mgmt`.

See [values.yaml](values.yaml) and the [Stalwart Kubernetes docs](https://stalw.art/docs/cluster/orchestration/kubernetes/).

## Clustering

Upstream model: `config.json` is only the DataStore. Coordinator is applied with [`stalwart-cli apply`](https://stalw.art/docs/management/cli/apply/). Postgres and the DB Secret stay outside the chart. Set `valkey.enabled: true` for the official Valkey dependency, or point `coordinator` at an external Redis/Valkey/NATS/Kafka.

When `coordinator` is set (or Valkey is enabled with an empty `coordinator`), a hook waits for `/healthz/ready` and applies the Coordinator. With `apply.rolloutRestart: true` (default) it then rolls the StatefulSet. Turn that off after the first HA cutover so routine chart upgrades do not bounce mail. `replicaCount > 1` fail-closes without a shared store, `persistence.enabled=false`, `coordinator` or `valkey.enabled`, and recovery-admin credentials.

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

**Brownfield:** snapshot the PVC, then one upgrade with `migration.enabled: true` and `migration.dataClaim` set ([migration docs](https://stalw.art/docs/management/maintenance/migration/)). A marker ConfigMap prevents re-runs; set `migration.enabled: false` afterward.
