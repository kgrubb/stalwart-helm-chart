#!/usr/bin/env bash
# One-off RocksDB → PostgreSQL migration for Stalwart on Kubernetes.
# See charts/stalwart/README.md — "Upgrading from 0.7.x to 0.8.x".
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: migrate-rocksdb-to-postgres.sh <export|import|all|cleanup>

  export   Run export Job (Stalwart must be scaled to 0 replicas).
  import   Run import Job (requires export dump on shared PVC).
  all      export, then import.
  cleanup  Delete migration Jobs, ConfigMap, and dump PVC.

Environment (defaults shown):

  NAMESPACE=stalwart
  DATA_CLAIM=data-stalwart-stalwart-0     # RocksDB PVC from the StatefulSet
  STATEFULSET=stalwart-stalwart           # used only for preflight replica check
  STALWART_IMAGE=stalwartlabs/stalwart:<chart appVersion>
  DUMP_CLAIM=stalwart-migrate-dump
  DUMP_SIZE=5Gi
  STORAGE_CLASS=longhorn
  DB_SECRET_NAME=stalwart-db              # must contain STALWART_DB_PASSWORD
  POSTGRES_HOST=postgres-rw.postgres.svc.cluster.local
  POSTGRES_PORT=5432
  POSTGRES_DATABASE=stalwart
  POSTGRES_USER=stalwart
  JOB_TIMEOUT=1h
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_YAML="${SCRIPT_DIR}/../charts/stalwart/Chart.yaml"

NAMESPACE="${NAMESPACE:-stalwart}"
DATA_CLAIM="${DATA_CLAIM:-data-stalwart-stalwart-0}"
STATEFULSET="${STATEFULSET:-stalwart-stalwart}"
DUMP_CLAIM="${DUMP_CLAIM:-stalwart-migrate-dump}"
DUMP_SIZE="${DUMP_SIZE:-5Gi}"
STORAGE_CLASS="${STORAGE_CLASS:-longhorn}"
DB_SECRET_NAME="${DB_SECRET_NAME:-stalwart-db}"
POSTGRES_HOST="${POSTGRES_HOST:-postgres-rw.postgres.svc.cluster.local}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DATABASE="${POSTGRES_DATABASE:-stalwart}"
POSTGRES_USER="${POSTGRES_USER:-stalwart}"
JOB_TIMEOUT="${JOB_TIMEOUT:-1h}"

if [[ -z "${STALWART_IMAGE:-}" ]]; then
  if [[ -f "$CHART_YAML" ]]; then
    tag="$(awk '/^appVersion:/ { gsub(/"/, "", $2); print $2 }' "$CHART_YAML")"
    STALWART_IMAGE="stalwartlabs/stalwart:${tag}"
  else
    STALWART_IMAGE="stalwartlabs/stalwart:latest"
  fi
fi

EXPORT_JOB=stalwart-migrate-export
IMPORT_JOB=stalwart-migrate-import
CONFIGMAP=stalwart-migrate-scripts

require_kubectl() {
  command -v kubectl >/dev/null 2>&1 || {
    echo "error: kubectl not found in PATH" >&2
    exit 1
  }
}

preflight_export() {
  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "error: namespace $NAMESPACE not found" >&2
    exit 1
  fi
  if ! kubectl get pvc -n "$NAMESPACE" "$DATA_CLAIM" >/dev/null 2>&1; then
    echo "error: PVC $DATA_CLAIM not found in $NAMESPACE" >&2
    exit 1
  fi
  if kubectl get statefulset -n "$NAMESPACE" "$STATEFULSET" >/dev/null 2>&1; then
    replicas="$(kubectl get statefulset -n "$NAMESPACE" "$STATEFULSET" -o jsonpath='{.spec.replicas}')"
    ready="$(kubectl get statefulset -n "$NAMESPACE" "$STATEFULSET" -o jsonpath='{.status.readyReplicas}')"
    if [[ "${replicas:-0}" -gt 0 || "${ready:-0}" -gt 0 ]]; then
      echo "error: scale $STATEFULSET to 0 before export:" >&2
      echo "  kubectl scale statefulset/$STATEFULSET -n $NAMESPACE --replicas=0" >&2
      exit 1
    fi
  fi
}

preflight_import() {
  if ! kubectl get secret -n "$NAMESPACE" "$DB_SECRET_NAME" >/dev/null 2>&1; then
    echo "error: secret $DB_SECRET_NAME not found in $NAMESPACE" >&2
    exit 1
  fi
  if ! kubectl get pvc -n "$NAMESPACE" "$DUMP_CLAIM" >/dev/null 2>&1; then
    echo "error: dump PVC $DUMP_CLAIM not found — run export first" >&2
    exit 1
  fi
}

apply_shared_resources() {
  kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${CONFIGMAP}
  namespace: ${NAMESPACE}
data:
  export.sh: |
    #!/bin/sh
    set -eu
    DUMP_DIR="\${DUMP_DIR:-/export/dump}"
    if [ ! -d /var/lib/stalwart ]; then
      echo "error: /var/lib/stalwart missing — check DATA_CLAIM PVC mount"
      exit 1
    fi
    rm -rf "\$DUMP_DIR"
    mkdir -p "\$DUMP_DIR"
    stalwart --config /etc/stalwart/config.json --export "\$DUMP_DIR"
    files=\$(find "\$DUMP_DIR" -type f | wc -l)
    if [ "\$files" -eq 0 ]; then
      echo "error: export produced no files"
      exit 1
    fi
    du -sh "\$DUMP_DIR"
    echo "export ok (\$files files)"
  import.sh: |
    #!/bin/sh
    set -eu
    DUMP_DIR="\${DUMP_DIR:-/export/dump}"
    if [ -z "\${STALWART_DB_PASSWORD:-}" ]; then
      echo "error: STALWART_DB_PASSWORD not set (${DB_SECRET_NAME} secret)"
      exit 1
    fi
    if [ ! -d "\$DUMP_DIR" ]; then
      echo "error: dump directory missing — run export first"
      exit 1
    fi
    files=\$(find "\$DUMP_DIR" -type f | wc -l)
    if [ "\$files" -eq 0 ]; then
      echo "error: dump is empty"
      exit 1
    fi
    stalwart --config /etc/stalwart/config.json --import "\$DUMP_DIR"
    echo "import ok (\$files files imported)"
  rocksdb-config.json: |
    {
      "@type": "RocksDb",
      "path": "/var/lib/stalwart"
    }
  postgres-config.json: |
    {
      "@type": "PostgreSql",
      "host": "${POSTGRES_HOST}",
      "port": ${POSTGRES_PORT},
      "database": "${POSTGRES_DATABASE}",
      "authUsername": "${POSTGRES_USER}",
      "authSecret": {
        "@type": "EnvironmentVariable",
        "variableName": "STALWART_DB_PASSWORD"
      }
    }
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${DUMP_CLAIM}
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${STORAGE_CLASS}
  resources:
    requests:
      storage: ${DUMP_SIZE}
EOF
}

run_job() {
  local job="$1"
  local manifest="$2"

  kubectl delete job -n "$NAMESPACE" "$job" --ignore-not-found=true
  kubectl apply -f - <<<"$manifest"
  kubectl wait -n "$NAMESPACE" --for=condition=complete "job/$job" --timeout="$JOB_TIMEOUT"
  kubectl logs -n "$NAMESPACE" "job/$job"
}

run_export() {
  preflight_export
  apply_shared_resources
  run_job "$EXPORT_JOB" "$(export_job_manifest)"
}

run_import() {
  preflight_import
  apply_shared_resources
  run_job "$IMPORT_JOB" "$(import_job_manifest)"
}

export_job_manifest() {
  cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${EXPORT_JOB}
  namespace: ${NAMESPACE}
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 3600
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: Never
      securityContext:
        fsGroup: 2000
        runAsUser: 2000
        runAsGroup: 2000
        runAsNonRoot: true
      initContainers:
        - name: verify-data-pvc
          image: busybox:1.37
          command:
            - /bin/sh
            - -ec
            - |
              test -d /var/lib/stalwart || exit 1
              ls -la /var/lib/stalwart | head -20
          volumeMounts:
            - name: data
              mountPath: /var/lib/stalwart
              readOnly: true
      containers:
        - name: export
          image: ${STALWART_IMAGE}
          command: ["/bin/sh", "/scripts/export.sh"]
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: data
              mountPath: /var/lib/stalwart
              readOnly: true
            - name: config
              mountPath: /etc/stalwart/config.json
              subPath: rocksdb-config.json
              readOnly: true
            - name: scripts
              mountPath: /scripts
              readOnly: true
            - name: export
              mountPath: /export
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: ${DATA_CLAIM}
        - name: config
          configMap:
            name: ${CONFIGMAP}
        - name: scripts
          configMap:
            name: ${CONFIGMAP}
            defaultMode: 0555
        - name: export
          persistentVolumeClaim:
            claimName: ${DUMP_CLAIM}
EOF
}

import_job_manifest() {
  cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${IMPORT_JOB}
  namespace: ${NAMESPACE}
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 3600
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: Never
      securityContext:
        fsGroup: 2000
        runAsUser: 2000
        runAsGroup: 2000
        runAsNonRoot: true
      initContainers:
        - name: verify-dump
          image: busybox:1.37
          command:
            - /bin/sh
            - -ec
            - |
              test -d /export/dump || exit 1
              files=\$(find /export/dump -type f | wc -l)
              test "\$files" -gt 0 || exit 1
              echo "dump ok (\$files files)"
          volumeMounts:
            - name: export
              mountPath: /export
              readOnly: true
      containers:
        - name: import
          image: ${STALWART_IMAGE}
          command: ["/bin/sh", "/scripts/import.sh"]
          envFrom:
            - secretRef:
                name: ${DB_SECRET_NAME}
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: config
              mountPath: /etc/stalwart/config.json
              subPath: postgres-config.json
              readOnly: true
            - name: scripts
              mountPath: /scripts
              readOnly: true
            - name: export
              mountPath: /export
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: ${CONFIGMAP}
        - name: scripts
          configMap:
            name: ${CONFIGMAP}
            defaultMode: 0555
        - name: export
          persistentVolumeClaim:
            claimName: ${DUMP_CLAIM}
EOF
}

cleanup() {
  kubectl delete job -n "$NAMESPACE" "$EXPORT_JOB" "$IMPORT_JOB" --ignore-not-found=true
  kubectl delete configmap -n "$NAMESPACE" "$CONFIGMAP" --ignore-not-found=true
  kubectl delete pvc -n "$NAMESPACE" "$DUMP_CLAIM" --ignore-not-found=true
  echo "cleanup ok"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    export)
      require_kubectl
      run_export
      ;;
    import)
      require_kubectl
      run_import
      ;;
    all)
      require_kubectl
      run_export
      run_import
      echo "migration complete — update Helm values to PostgreSql, redeploy, then run: $0 cleanup"
      ;;
    cleanup)
      require_kubectl
      cleanup
      ;;
    -h | --help | help | "")
      usage
      [[ -n "$cmd" ]] || exit 0
      ;;
    *)
      echo "error: unknown command: $cmd" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
