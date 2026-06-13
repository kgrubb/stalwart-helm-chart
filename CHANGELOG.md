# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
