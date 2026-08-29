{{- define "waterway-safety.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "waterway-safety.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "waterway-safety.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "waterway-safety.labels" -}}
app.kubernetes.io/name: {{ include "waterway-safety.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end -}}

{{- define "waterway-safety.selectorLabels" -}}
app.kubernetes.io/name: {{ include "waterway-safety.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "waterway-safety.secretName" -}}
{{- printf "%s-env" (include "waterway-safety.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
