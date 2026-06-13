# stalwart

Helm chart for [Stalwart Mail Server](https://stalw.art/), based on the [official Kubernetes reference](https://stalw.art/docs/cluster/orchestration/kubernetes/).

## Install

```bash
helm repo add kgrubb-stalwart https://kgrubb.github.io/stalwart-helm-chart
helm repo update
helm install stalwart kgrubb-stalwart/stalwart -n mail --create-namespace
```

Chart index: https://kgrubb.github.io/stalwart-helm-chart/index.yaml

## First install

Enable bootstrap credentials, sign in at `/admin`, then disable them:

```yaml
recoveryAdmin:
  enabled: true
  password: "choose-a-strong-password"
```

## Releases

Pushes to `main` that change `charts/` bump the chart version from conventional commits (`feat:` minor, breaking major, otherwise patch), publish with [chart-releaser](https://github.com/helm/chart-releaser-action), and host `index.yaml` plus packages on `gh-pages`.

## Development

```bash
helm lint charts/stalwart --strict
helm template test charts/stalwart
```
