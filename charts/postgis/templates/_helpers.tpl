{{- define "postgis.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "postgis.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "postgis.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "postgis.labels" -}}
app.kubernetes.io/name: {{ include "postgis.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end -}}

{{- define "postgis.selectorLabels" -}}
app.kubernetes.io/name: {{ include "postgis.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "postgis.imageRef" -}}
{{- if eq .Values.image.variant "cloudnative-pg" -}}
{{- printf "%s@%s" .Values.image.cloudnativePG.repository .Values.image.cloudnativePG.digest -}}
{{- else -}}
{{- printf "%s@%s" .Values.image.postgisImage.repository .Values.image.postgisImage.digest -}}
{{- end -}}
{{- end -}}
