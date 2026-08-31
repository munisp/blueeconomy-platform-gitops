{{- define "cilium.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cilium.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "cilium.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "cilium.labels" -}}
app.kubernetes.io/name: {{ include "cilium.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end -}}

{{/* Approved workstream catalogue, mirroring charts/dapr-components. */}}
{{- define "cilium.approvedAppIds" -}}
{{- dict
  "ports" (list "port-interoperability-api" "ussd-gateway" "booking-worker" "ports-outbox-publisher")
  "ferries" (list "ferry-api" "ferry-worker" "ferry-outbox-publisher")
  "cvff" (list "intent-api" "cvff-worker" "cvff-outbox-publisher")
  "seafarer" (list "credential-verification-api" "seafarer-credential-worker")
  "fisheries" (list "trace-api" "trace-worker" "fisheries-outbox-publisher")
  "isr" (list "maritime-intelligence-api" "isr-worker" "isr-outbox-publisher")
| toJson -}}
{{- end -}}
