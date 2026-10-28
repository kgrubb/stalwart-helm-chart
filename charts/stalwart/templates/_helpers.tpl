{{/* Expand the name of the chart. */}}
{{- define "stalwart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "stalwart.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "stalwart.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "stalwart.labels" -}}
app.kubernetes.io/name: {{ include "stalwart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "stalwart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "stalwart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "stalwart.serverSelectorLabels" -}}
{{- include "stalwart.selectorLabels" . }}
app.kubernetes.io/component: server
{{- end -}}

{{- define "stalwart.bootstrapLabels" -}}
app.kubernetes.io/component: bootstrap
app.kubernetes.io/part-of: {{ include "stalwart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "stalwart.hasCoordinator" -}}
{{- if or (not (empty .Values.coordinator)) .Values.valkey.enabled -}}true{{- end -}}
{{- end -}}

{{- define "stalwart.valkey.url" -}}
{{- $vk := dict "Release" .Release "Chart" (dict "Name" "valkey") "Values" .Values.valkey -}}
redis://{{ include "valkey.fullname" $vk }}.{{ .Release.Namespace }}.svc:{{ dig "service" "port" 6379 .Values.valkey }}
{{- end -}}

{{- define "stalwart.inMemoryObject" -}}
{{- if not (empty .Values.inMemoryStore) -}}
{{- .Values.inMemoryStore | toJson -}}
{{- else if .Values.valkey.enabled -}}
{{- if dig "auth" "enabled" false .Values.valkey -}}
{{- fail "valkey.auth.enabled requires an explicit inMemoryStore url with credentials" -}}
{{- end -}}
{{- dict "@type" "Redis" "url" (include "stalwart.valkey.url" .) | toJson -}}
{{- else if and (not (empty .Values.coordinator)) (eq (index .Values.coordinator "@type" | toString) "Redis") (index .Values.coordinator "url") -}}
{{- dict "@type" "Redis" "url" (index .Values.coordinator "url") | toJson -}}
{{- else -}}
{}
{{- end -}}
{{- end -}}

{{- define "stalwart.coordinatorObject" -}}
{{- if not (empty .Values.coordinator) -}}
{{- .Values.coordinator | toJson -}}
{{- else if .Values.valkey.enabled -}}
{{- if dig "auth" "enabled" false .Values.valkey -}}
{{- fail "valkey.auth.enabled requires an explicit coordinator url with credentials" -}}
{{- end -}}
{{- dict "@type" "Redis" "url" (include "stalwart.valkey.url" .) | toJson -}}
{{- else -}}
{}
{{- end -}}
{{- end -}}

{{- define "stalwart.recoveryAdminOnPod" -}}
{{- or .Values.recoveryAdmin.enabled (and .Values.bootstrap.enabled .Values.recoveryAdmin.existingSecret) (and (include "stalwart.hasCoordinator" .) .Values.recoveryAdmin.existingSecret) (include "stalwart.mailTls.enabled" .) -}}
{{- end -}}

{{- define "stalwart.v1MarkerName" -}}
{{- printf "%s-v1-migrated" (include "stalwart.fullname" .) -}}
{{- end -}}

{{- define "stalwart.cluster.validate" -}}
{{- if and .Values.migration.enabled .Values.v1Migrate.enabled -}}
{{- fail "migration.enabled and v1Migrate.enabled cannot both be true" -}}
{{- end -}}
{{- if and .Release.IsUpgrade (not .Values.v1Migrate.enabled) (not .Values.v1Migrate.alreadyDone) (not (lookup "v1" "ConfigMap" .Release.Namespace (include "stalwart.v1MarkerName" .))) -}}
{{- fail "Stalwart 1.0 cannot open a 0.16 store. Enable v1Migrate (see chart README), or set v1Migrate.alreadyDone=true if this release already runs 1.0." -}}
{{- end -}}
{{- if .Values.v1Migrate.enabled -}}
{{- if empty .Values.v1Migrate.sourceConfig -}}
{{- fail "v1Migrate.enabled requires v1Migrate.sourceConfig (the live 0.16 DataStore)" -}}
{{- end -}}
{{- if eq (.Values.v1Migrate.sourceConfig | toJson) (.Values.config | toJson) -}}
{{- fail "v1Migrate.sourceConfig must differ from config (config is the empty 1.0 target store)" -}}
{{- end -}}
{{- $mem := include "stalwart.inMemoryObject" . | fromJson -}}
{{- if or (ne (index $mem "@type" | toString) "Redis") (not (index $mem "url")) -}}
{{- fail "v1Migrate requires Redis inMemoryStore with url (or valkey.enabled)" -}}
{{- end -}}
{{- end -}}
{{- if include "stalwart.hasCoordinator" . -}}
{{- if eq (include "stalwart.inMemoryObject" .) "{}" -}}
{{- fail "coordinator/valkey requires inMemoryStore (Redis) or valkey.enabled" -}}
{{- end -}}
{{- end -}}
{{- if gt (.Values.replicaCount | int) 1 -}}
{{- if eq (index .Values.config "@type" | toString) "RocksDb" -}}
{{- fail "replicaCount > 1 requires a shared DataStore (config.@type must not be RocksDb)" -}}
{{- end -}}
{{- if .Values.persistence.enabled -}}
{{- fail "replicaCount > 1 requires persistence.enabled=false" -}}
{{- end -}}
{{- if not (include "stalwart.hasCoordinator" .) -}}
{{- fail "replicaCount > 1 requires coordinator or valkey.enabled" -}}
{{- end -}}
{{- if and (not .Values.recoveryAdmin.existingSecret) (not .Values.recoveryAdmin.password) -}}
{{- fail "replicaCount > 1 requires recoveryAdmin credentials for the coordinator apply Job" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* answers.toml defaults for stalwart-migrate prepare --non-interactive */}}
{{- define "stalwart.v1Migrate.answers" -}}
version = 1

[global.categories]
include = [
  "settings",
  "principals",
  "mail",
  "calendars",
  "contacts",
  "files",
  "sieve",
  "identities",
  "push_subscriptions",
  "spam_samples",
  "reports",
  "archive",
  "spam_model",
  "queue",
  "tasks",
]

[global.changed_defaults]
policy = "recommended"

[global.blob_store]
mode = "reuse"

[instance.oauth_registration."x:OidcProvider"]
action = "accept"

[instance.http_forwarded."x:Http"]
source = "xForwardedFor"
hops = 1

[instance.in_memory_cluster."x:InMemoryStore"]
action = "replace"

[instance.in_memory_cluster."x:InMemoryStore".store]
{{- $mem := include "stalwart.inMemoryObject" . | fromJson }}
"@type" = "Redis"
url = {{ index $mem "url" | quote }}
{{- with .Values.v1Migrate.answers }}

{{ . }}
{{- end }}
{{- end -}}

{{- define "stalwart.needsChartEnvSecret" -}}
{{- $inline := and (not .Values.recoveryAdmin.existingSecret) .Values.recoveryAdmin.password -}}
{{- if or (not (empty .Values.extraSecretEnv)) (and (include "stalwart.recoveryAdminOnPod" .) (not .Values.recoveryAdmin.existingSecret) $inline) (and (include "stalwart.hasCoordinator" .) $inline) -}}true{{- end -}}
{{- end -}}

{{- define "stalwart.recoveryAdmin.env" -}}
- name: RECOVERY_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ .Values.recoveryAdmin.existingSecret }}
      key: {{ .Values.recoveryAdmin.usernameKey }}
- name: RECOVERY_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.recoveryAdmin.existingSecret }}
      key: {{ .Values.recoveryAdmin.passwordKey }}
- name: STALWART_RECOVERY_ADMIN
  value: "$(RECOVERY_USERNAME):$(RECOVERY_PASSWORD)"
{{- end -}}

{{- define "stalwart.apply.authEnv" -}}
{{- if .Values.recoveryAdmin.existingSecret }}
- name: STALWART_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.recoveryAdmin.existingSecret }}
      key: {{ .Values.recoveryAdmin.usernameKey }}
- name: STALWART_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.recoveryAdmin.existingSecret }}
      key: {{ .Values.recoveryAdmin.passwordKey }}
{{- else }}
- name: STALWART_USER
  value: {{ .Values.recoveryAdmin.username | quote }}
- name: STALWART_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "stalwart.fullname" . }}-env
      key: STALWART_RECOVERY_PASSWORD
{{- end }}
{{- end -}}

{{/* noDrop skips capability drop. Stalwart binaries EPERM under drop-all. */}}
{{- define "stalwart.hooks.containerSecurity" -}}
securityContext:
  allowPrivilegeEscalation: false
  {{- if not .noDrop }}
  capabilities:
    drop: ["ALL"]
  {{- end }}
  runAsNonRoot: true
  {{- if .uid }}
  runAsUser: {{ .uid }}
  runAsGroup: {{ .gid | default .uid }}
  {{- end }}
{{- end -}}

{{- define "stalwart.mailTls.enabled" -}}
{{- and .Values.mailTls.enabled .Values.mailTls.existingSecret -}}
{{- end -}}

{{- define "stalwart.mailTls.hostname" -}}
{{- default (index .Values.ingress.hosts 0 "host") .Values.mailTls.hostname -}}
{{- end -}}

{{- define "stalwart.mailServiceName" -}}
{{- if .Values.mailService.name -}}
{{- .Values.mailService.name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-mail" (include "stalwart.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
