{{- define "ferry-ticketing.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "ferry-ticketing.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "ferry-ticketing.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "ferry-ticketing.labels" -}}
app.kubernetes.io/name: {{ include "ferry-ticketing.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
blueeconomy.platform/workstream: {{ .Values.workstream | quote }}
{{- end -}}

{{- define "ferry-ticketing.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ferry-ticketing.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "ferry-ticketing.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "ferry-ticketing.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- required "serviceAccount.name is required when serviceAccount.create=false" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "ferry-ticketing.secretName" -}}
{{- printf "%s-secrets" (include "ferry-ticketing.fullname" .) -}}
{{- end -}}
