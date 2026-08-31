{{- define "port-interoperability.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "port-interoperability.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "port-interoperability.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "port-interoperability.labels" -}}
app.kubernetes.io/name: {{ include "port-interoperability.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
blueeconomy.platform/workstream: {{ .Values.workstream | quote }}
{{- end -}}

{{- define "port-interoperability.selectorLabels" -}}
app.kubernetes.io/name: {{ include "port-interoperability.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "port-interoperability.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "port-interoperability.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- required "serviceAccount.name is required when serviceAccount.create=false" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "port-interoperability.secretName" -}}
{{- printf "%s-secrets" (include "port-interoperability.fullname" .) -}}
{{- end -}}
