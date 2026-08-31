{{- define "ml-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "ml-stack.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "ml-stack.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "ml-stack.labels" -}}
app.kubernetes.io/name: {{ include "ml-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end -}}

{{- define "ml-stack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ml-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "ml-stack.secretName" -}}
{{- printf "%s-env" (include "ml-stack.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- /* Shared container env for all components. */ -}}
{{- define "ml-stack.containerEnv" -}}
{{- $ := . -}}
{{- range $key := (default (list) .Values.secretEnv) }}
- name: {{ $key | quote }}
  valueFrom:
    secretKeyRef:
      name: {{ include "ml-stack.secretName" $ | quote }}
      key: {{ $key | quote }}
{{- end }}
{{- end -}}
