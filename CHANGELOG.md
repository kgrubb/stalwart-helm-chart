# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
