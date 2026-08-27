{{- define "dapr-components.labels" -}}
app.kubernetes.io/name: dapr-components
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
blueeconomy.platform/workstream: {{ .Values.workstream.name | quote }}
{{- end -}}

{{- define "dapr-components.secretName" -}}
{{- printf "dapr-%s-components" .Values.workstream.name -}}
{{- end -}}
