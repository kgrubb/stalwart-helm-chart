#!/usr/bin/env bash
# One-off RocksDB → PostgreSQL migration (runs as a single in-cluster Job).
# See charts/stalwart/README.md — "Upgrading from 0.7.x to 0.8.x".
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tpl="${dir}/migrate-rocksdb-to-postgres.yaml.tpl"
job=stalwart-migrate

usage() {
  cat <<EOF
Usage: $(basename "$0") [namespace] [cleanup]

  $(basename "$0")              migrate (default namespace: stalwart)
  $(basename "$0") mail         migrate in another namespace
  $(basename "$0") cleanup      delete migration Job, ConfigMap, and dump PVC

Optional env (defaults are fine for most installs):
  DATA_CLAIM, DB_SECRET_NAME, POSTGRES_HOST, POSTGRES_DATABASE, POSTGRES_USER
  SKIP_SCALE_DOWN=1             do not scale Stalwart to 0 first

Requires: kubectl, envsubst. Creates Job/${job} in the target namespace.
EOF
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: $1 not found" >&2
    exit 1
  }
}

detect() {
  local ns="$1"
  if [[ -z "${DATA_CLAIM:-}" ]]; then
    DATA_CLAIM="$(kubectl get pvc -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
      | grep -E '^data-.+-0$' | head -1 || true)"
  fi
  [[ -n "$DATA_CLAIM" ]] || {
    echo "error: no RocksDB PVC (data-*-0) in $ns — set DATA_CLAIM" >&2
    exit 1
  }

  if [[ -z "${STALWART_IMAGE:-}" ]]; then
    STALWART_IMAGE="$(kubectl get sts -n "$ns" -l app.kubernetes.io/name=stalwart \
      -o jsonpath='{.items[0].spec.template.spec.containers[0].image}' 2>/dev/null || true)"
    if [[ -z "$STALWART_IMAGE" && -f "${dir}/../charts/stalwart/Chart.yaml" ]]; then
      tag="$(awk '/^appVersion:/ { gsub(/"/, "", $2); print $2 }' "${dir}/../charts/stalwart/Chart.yaml")"
      STALWART_IMAGE="stalwartlabs/stalwart:${tag}"
    fi
    STALWART_IMAGE="${STALWART_IMAGE:-stalwartlabs/stalwart:latest}"
  fi

  if [[ -z "${STORAGE_CLASS:-}" ]]; then
    STORAGE_CLASS="$(kubectl get pvc -n "$ns" "$DATA_CLAIM" -o jsonpath='{.spec.storageClassName}')"
    STORAGE_CLASS="${STORAGE_CLASS:-standard}"
  fi
}

scale_down() {
  local ns="$1" sts
  sts="$(kubectl get sts -n "$ns" -l app.kubernetes.io/name=stalwart -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [[ -n "$sts" ]] || return 0
  replicas="$(kubectl get sts -n "$ns" "$sts" -o jsonpath='{.spec.replicas}')"
  [[ "${replicas:-0}" -eq 0 ]] && return 0
  echo "scaling $sts to 0..."
  kubectl scale "sts/$sts" -n "$ns" --replicas=0
  kubectl wait -n "$ns" --for=delete pod -l app.kubernetes.io/name=stalwart --timeout=300s
}

run() {
  local ns="$1"
  need kubectl
  need envsubst

  NAMESPACE="$ns"
  DB_SECRET_NAME="${DB_SECRET_NAME:-stalwart-db}"
  POSTGRES_HOST="${POSTGRES_HOST:-postgres-rw.postgres.svc.cluster.local}"
  POSTGRES_PORT="${POSTGRES_PORT:-5432}"
  POSTGRES_DATABASE="${POSTGRES_DATABASE:-stalwart}"
  POSTGRES_USER="${POSTGRES_USER:-stalwart}"

  kubectl get namespace "$ns" >/dev/null
  kubectl get secret -n "$ns" "$DB_SECRET_NAME" >/dev/null

  detect "$ns"
  if [[ "${SKIP_SCALE_DOWN:-0}" != 1 ]]; then
    scale_down "$ns"
  fi

  kubectl delete job -n "$ns" "$job" --ignore-not-found=true
  export NAMESPACE DATA_CLAIM STALWART_IMAGE STORAGE_CLASS DB_SECRET_NAME
  export POSTGRES_HOST POSTGRES_PORT POSTGRES_DATABASE POSTGRES_USER
  envsubst <"$tpl" | kubectl apply -f -

  echo "waiting for Job/${job}..."
  kubectl wait -n "$ns" --for=condition=complete "job/$job" --timeout=1h
  kubectl logs -n "$ns" "job/$job"
  echo "done — upgrade Helm values to PostgreSql, redeploy, then: $(basename "$0") cleanup $ns"
}

cleanup() {
  local ns="$1"
  need kubectl
  kubectl delete job -n "$ns" "$job" --ignore-not-found=true
  kubectl delete configmap -n "$ns" stalwart-migrate --ignore-not-found=true
  kubectl delete pvc -n "$ns" stalwart-migrate-dump --ignore-not-found=true
  echo "cleanup ok"
}

main() {
  local ns="${NAMESPACE:-stalwart}"
  case "${1:-}" in
    -h | --help | help)
      usage
      ;;
    cleanup)
      cleanup "${2:-$ns}"
      ;;
    "")
      run "$ns"
      ;;
    *)
      case "${2:-}" in
        cleanup) cleanup "$1" ;;
        *) run "$1" ;;
      esac
      ;;
  esac
}

main "$@"
