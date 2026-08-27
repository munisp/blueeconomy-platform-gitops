{{- define "security-operations.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "security-operations.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "security-operations.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "security-operations.labels" -}}
app.kubernetes.io/name: {{ include "security-operations.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
blueeconomy.platform/workstream: {{ .Values.workstream | quote }}
{{- end -}}

{{- define "security-operations.selectorLabels" -}}
app.kubernetes.io/name: {{ include "security-operations.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "security-operations.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "security-operations.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- required "serviceAccount.name is required when serviceAccount.create=false" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "security-operations.secretName" -}}
{{- printf "%s-secrets" (include "security-operations.fullname" .) -}}
{{- end -}}
