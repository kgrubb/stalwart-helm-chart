# Render with envsubst (see migrate-rocksdb-to-postgres.sh).
apiVersion: v1
kind: ConfigMap
metadata:
  name: stalwart-migrate
  namespace: ${NAMESPACE}
data:
  migrate.sh: |
    #!/bin/sh
    set -eu
    DUMP=/export/dump
    rm -rf "$DUMP" && mkdir -p "$DUMP"
    stalwart --config /config/rocksdb.json --export "$DUMP"
    test "$(find "$DUMP" -type f | wc -l)" -gt 0
    stalwart --config /config/postgres.json --import "$DUMP"
    echo "migration ok"
  rocksdb.json: |
    {"@type":"RocksDb","path":"/var/lib/stalwart"}
  postgres.json: |
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
  name: stalwart-migrate-dump
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${STORAGE_CLASS}
  resources:
    requests:
      storage: 5Gi
---
apiVersion: batch/v1
kind: Job
metadata:
  name: stalwart-migrate
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
      containers:
        - name: migrate
          image: ${STALWART_IMAGE}
          command: ["/bin/sh", "/scripts/migrate.sh"]
          envFrom:
            - secretRef:
                name: ${DB_SECRET_NAME}
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
              mountPath: /config
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
            name: stalwart-migrate
        - name: scripts
          configMap:
            name: stalwart-migrate
            defaultMode: 0555
        - name: export
          persistentVolumeClaim:
            claimName: stalwart-migrate-dump
