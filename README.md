# stalwart-helm-chart

Community-maintained Helm chart for [Stalwart Mail Server](https://stalw.art/), based on the [official Kubernetes reference chart](https://stalw.art/docs/cluster/orchestration/kubernetes/).

Chart source: [Stalwart Labs Kubernetes documentation](https://stalw.art/docs/cluster/orchestration/kubernetes/). Stalwart itself is developed by [Stalwart Labs](https://github.com/stalwartlabs/stalwart).

## Install

```bash
helm repo add kgrubb-stalwart https://kgrubb.github.io/stalwart-helm-chart
helm repo update
helm install stalwart kgrubb-stalwart/stalwart \
  --namespace mail --create-namespace \
  -f values.yaml
```

## Upgrade

```bash
helm upgrade stalwart kgrubb-stalwart/stalwart -n mail -f values.yaml
```

## Configuration

See [values.yaml](charts/stalwart/values.yaml) and the [Stalwart Kubernetes docs](https://stalw.art/docs/cluster/orchestration/kubernetes/) for DataStore options, clustering, ingress, LoadBalancer mail ports, and restricted Pod Security Standards.

On first install, enable `recoveryAdmin` to sign in at `/admin`, complete the setup wizard, then disable `recoveryAdmin` for production.

## Releases

Pushes to `main` that change files under `charts/` trigger [chart-releaser-action](https://github.com/helm/chart-releaser-action):

1. Chart version is bumped from conventional commit messages in the merge:
   - `feat:` → minor
   - `fix:`, `chore:`, `docs:`, etc. → patch (default when no recognized prefix)
   - `BREAKING CHANGE` or `type!:` → major
2. The bumped `Chart.yaml` is committed as `chore(release): bump chart to x.y.z`
3. chart-releaser publishes the package and updates `gh-pages`

### GitHub Pages setup (one-time)

After the first workflow run:

1. Repo **Settings → Pages**
2. Source: deploy from branch **`gh-pages`** / root

## Development

```bash
helm lint charts/stalwart
helm template stalwart charts/stalwart
```

## License

Chart templates follow the Stalwart documentation reference. Stalwart Mail Server is licensed under its upstream license.
