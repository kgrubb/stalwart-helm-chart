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

## Upgrading to HA

Defaults stay single-node RocksDB. Multi-replica installs need a shared DataStore (PostgreSQL, FoundationDB, etc.) and a Coordinator in the WebUI. See [data store](https://stalw.art/docs/storage/data/) and [migration](https://stalw.art/docs/management/maintenance/migration/).

| Key | Default | When enabling HA |
| --- | --- | --- |
| `envFrom` | `[]` | Mount secrets (e.g. `STALWART_DB_PASSWORD`) |
| `affinity` / `topologySpreadConstraints` | empty | Spread pods across nodes |
| `podDisruptionBudget.enabled` | `false` | `true` with multiple replicas |
| `metrics.serviceMonitor.enabled` | `false` | Prometheus Operator scrape |

```yaml
replicaCount: 2
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
