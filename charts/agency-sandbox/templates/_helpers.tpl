{{- define "agency-sandbox.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "agency-sandbox.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "agency-sandbox.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "agency-sandbox.labels" -}}
app.kubernetes.io/name: {{ include "agency-sandbox.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
environment: sandbox
{{- end -}}

{{- define "agency-sandbox.selectorLabels" -}}
app.kubernetes.io/name: {{ include "agency-sandbox.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
environment: sandbox
{{- end -}}

{{- define "agency-sandbox.secretName" -}}
{{- printf "%s-env" (include "agency-sandbox.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
