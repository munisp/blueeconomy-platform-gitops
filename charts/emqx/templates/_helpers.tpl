{{- define "emqx.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "emqx.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "emqx.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "emqx.labels" -}}
app.kubernetes.io/name: {{ include "emqx.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end -}}

{{- define "emqx.selectorLabels" -}}
app.kubernetes.io/name: {{ include "emqx.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "emqx.secretName" -}}
{{- printf "%s-env" (include "emqx.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "emqx.headlessName" -}}
{{- printf "%s-headless" (include "emqx.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
