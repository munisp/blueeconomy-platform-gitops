{{- define "opa-policies.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "opa-policies.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "opa-policies.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "opa-policies.labels" -}}
app.kubernetes.io/name: {{ include "opa-policies.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end -}}

{{- define "opa-policies.selectorLabels" -}}
app.kubernetes.io/name: opa
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "opa-policies.keyDirectoryName" -}}
{{- printf "%s-key-directory" (include "opa-policies.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "opa-policies.serviceName" -}}
{{- default "opa" .Values.apisixHook.serviceName -}}
{{- end -}}
