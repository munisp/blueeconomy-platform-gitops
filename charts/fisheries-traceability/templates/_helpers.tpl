{{- define "fisheries-traceability.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "fisheries-traceability.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "fisheries-traceability.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "fisheries-traceability.labels" -}}
app.kubernetes.io/name: {{ include "fisheries-traceability.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
blueeconomy.platform/workstream: {{ .Values.workstream | quote }}
{{- end -}}

{{- define "fisheries-traceability.selectorLabels" -}}
app.kubernetes.io/name: {{ include "fisheries-traceability.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "fisheries-traceability.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "fisheries-traceability.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- required "serviceAccount.name is required when serviceAccount.create=false" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "fisheries-traceability.secretName" -}}
{{- printf "%s-secrets" (include "fisheries-traceability.fullname" .) -}}
{{- end -}}
