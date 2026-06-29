# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.2] - 2026-06-29

### Fixed
- mailService migration and tls-sync startup ([#29](https://github.com/kgrubb/stalwart-helm-chart/pull/29))
  - **tls-sync**: poll every 10s while cert-manager TLS files are missing or JMAP is unreachable, instead of sleeping for the full `reloadIntervalSeconds`. Fixes implicit-TLS SMTP/IMAP listeners accepting TCP but resetting TLS handshakes until the next slow poll cycle after pod restarts.
  - **mailService.name**: optional Service name override (e.g. `stalwart-mail`) so GitOps migrations can drop a hand-maintained LoadBalancer manifest and let Helm manage the same Service name + MetalLB IP without creating a second `*-mail` Service.
  - **startupProbe**: give Stalwart up to ~5 minutes on RocksDB recovery before liveness/readiness failures during restarts.



### Fixed
- **mailTls tls-sync**: poll every 10s while cert-manager files are missing or JMAP is unreachable, instead of sleeping for the full reload interval. Prevents implicit-TLS mail listeners from staying broken after pod restarts.
- **mailService**: optional `mailService.name` for adopting a hand-maintained LoadBalancer Service name during GitOps migration.
- **probes**: add a `startupProbe` so slow RocksDB recovery on restart does not trip liveness before the management listener is ready.

## [0.7.1] - 2026-06-29

### Fixed
- set GH_TOKEN for upgrade-stalwart workflow ([#28](https://github.com/kgrubb/stalwart-helm-chart/pull/28))
  - Fixes the Upgrade Stalwart workflow failing with exit code 4
  - Adds `GH_TOKEN: ${{ github.token }}` to the upgrade step so `gh api` can fetch the latest Stalwart release



## [0.7.0] - 2026-06-28

### Added
- optional mailService LoadBalancer for L4 mail ports ([#27](https://github.com/kgrubb/stalwart-helm-chart/pull/27))
  - Add `mailService` values block to expose SMTP/IMAP/POP3/Sieve on a dedicated LoadBalancer Service.
  - Keeps the main `service` ClusterIP for ingress to the management listener (Traefik + cert-manager pattern).



### Added
- Optional `mailService` LoadBalancer for L4 mail ports while the main Service stays ClusterIP for ingress.

## [0.6.2] - 2026-06-28

### Fixed
- use exec probes for management health checks ([#26](https://github.com/kgrubb/stalwart-helm-chart/pull/26))
  - Replace kubelet `httpGet` liveness/readiness probes with `exec` probes that `curl` the management health endpoints on `127.0.0.1`.
  - On k3s/Flannel, probes from the node bridge to the pod IP can fail with connection reset/EOF while Stalwart is healthy, causing CrashLoopBackOff.



### Fixed
- Use exec probes against the management listener on localhost. On some CNIs (e.g. k3s/Flannel), kubelet `httpGet` checks to the pod IP can fail with connection reset while Stalwart is healthy.

## [0.6.1] - 2026-06-28

### Changed
- auto-sync Stalwart releases ([#25](https://github.com/kgrubb/stalwart-helm-chart/pull/25))
  - Add a daily workflow that checks [Stalwart releases](https://github.com/stalwartlabs/stalwart/releases) and bumps `image.tag` and `appVersion` when a newer version is published.
  - Map upstream semver to conventional commit prefixes (`fix:` patch, `feat:` minor, `feat!:` major) so the existing release workflow publishes the chart.
  - Document automatic release syncing in the README.



## [0.6.0] - 2026-06-26

### Changed
- Chart update



## [0.5.3] - 2026-06-26

### Changed
- Chart update



## [0.5.2] - 2026-06-26

### Changed
- Chart update



## [0.5.1] - 2026-06-26

### Changed
- Chart update



## [0.5.0] - 2026-06-26

### Changed
- Chart update



## [0.4.1] - 2026-06-26

### Changed
- Chart update



## [0.4.0] - 2026-06-26

### Added
- add recovery admin existingSecret and OIDC bootstrap ([#24](https://github.com/kgrubb/stalwart-helm-chart/pull/24))



## [0.3.0] - 2026-06-21

### Added
- bump Stalwart to v0.16.10 ([#23](https://github.com/kgrubb/stalwart-helm-chart/pull/23))
  - Update the Stalwart image from v0.16.8 to the latest release, v0.16.10.
  - Bumps both image.tag (values.yaml) and appVersion (Chart.yaml).



## [0.2.9] - 2026-06-21

### Changed
- satisfy kube-linter and yamllint ([#22](https://github.com/kgrubb/stalwart-helm-chart/pull/22))
  - Harden the default pod/container securityContext so the kube-linter security checks pass for real: runAsNonRoot, allowPrivilegeEscalation: false, drop all capabilities (keeping NET_BIND_SERVICE for the privileged mail ports), and RuntimeDefault seccomp.
  - Suppress the dangling-service false positive on both Services via a scoped ignore-check.kube-linter.io annotation -- the backing StatefulSet is invisible to kube-linter when deployed through a HelmChart CRD.
  - Add .kube-linter.yaml excluding only deployment-specific checks (unset-cpu/memory-requirements, no-read-only-root-filesystem).
  - Add .yamllint that ignores Helm templates, allows the GitHub Actions on: key, disables document-start, and sets line length to 120.



## [0.2.8] - 2026-06-13

### Fixed
- generate changelog from squash-merged PR commits ([#21](https://github.com/kgrubb/stalwart-helm-chart/pull/21))
  - Read PR numbers from squash commit subjects instead of merge commits
  - Skip chore(release) bot commits
  - Map chore, docs, and ci prefixes to Changed



## [0.2.7] - 2026-06-13

### Changed
- Chart update



## [0.2.5] - 2026-06-13

### Changed
- Chart update



## [0.2.4] - 2026-06-13

### Changed
- Chart update



## [0.2.3] - 2026-06-13

### Changed
- Chart update



## [0.2.1] - 2026-06-13

### Changed
- Chart update



## [0.2.0] - 2026-06-13

### Added
- generate Keep a Changelog release notes from merged PRs ([#4](https://github.com/kgrubb/stalwart-helm-chart/pull/4))
  - Generates Keep a Changelog release notes from merged PR `## Summary` bullets, categorized by conventional PR titles
  - Writes `charts/stalwart/RELEASE-NOTES.md` for chart-releaser and prepends each release to `CHANGELOG.md`



## [0.1.1] - 2026-06-13

### Fixed
- Harden chart templates and simplify release automation ([#1](https://github.com/kgrubb/stalwart-helm-chart/pull/1))
  - Fixes invalid empty `Secret`/`envFrom` rendering when `recoveryAdmin` is disabled
  - Simplifies release workflow to a single bump → chart-releaser → commit path
  - Publishes chart packages on `gh-pages` via `packages-with-index: true`
  - Adds a `CI` workflow for `helm lint --strict` and template rendering
  - Trims docs/values defaults (`recoveryAdmin.enabled: false`, no placeholder password in git)

## [0.1.0] - 2026-06-13

### Added
- Initial Stalwart Helm chart
