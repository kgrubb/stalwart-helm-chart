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

{{- define "stalwart.cluster.validate" -}}
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

{{- define "stalwart.hooks.containerSecurity" -}}
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  {{- with .uid }}
  runAsUser: {{ . }}
  runAsGroup: {{ . }}
  runAsNonRoot: true
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
