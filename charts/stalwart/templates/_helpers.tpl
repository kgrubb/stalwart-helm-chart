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

{{- define "stalwart.recoveryAdminOnPod" -}}
{{- or .Values.recoveryAdmin.enabled (and .Values.bootstrap.enabled .Values.recoveryAdmin.existingSecret) -}}
{{- end -}}

{{- define "stalwart.needsChartEnvSecret" -}}
{{- $inline := and (not .Values.recoveryAdmin.existingSecret) .Values.recoveryAdmin.password -}}
{{- if or (not (empty .Values.extraSecretEnv)) (and (include "stalwart.recoveryAdminOnPod" .) (not .Values.recoveryAdmin.existingSecret) $inline) -}}true{{- end -}}
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
