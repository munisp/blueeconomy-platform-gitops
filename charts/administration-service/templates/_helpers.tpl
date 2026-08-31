{{- define "administration-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "administration-service.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "administration-service.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "administration-service.labels" -}}
app.kubernetes.io/name: {{ include "administration-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end -}}

{{- define "administration-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "administration-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "administration-service.secretName" -}}
{{- printf "%s-env" (include "administration-service.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "administration-service.pbacConfigMapName" -}}
{{- printf "%s-pbac" (include "administration-service.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
