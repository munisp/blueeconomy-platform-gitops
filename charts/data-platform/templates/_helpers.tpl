{{- define "data-platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "data-platform.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "data-platform.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "data-platform.labels" -}}
app.kubernetes.io/name: {{ include "data-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end -}}

{{- define "data-platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "data-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "data-platform.secretName" -}}
{{- printf "%s-env" (include "data-platform.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- /* Shared job-pod env: storage convention, key directory, SASL via
       ExternalSecrets. */ -}}
{{- define "data-platform.jobEnv" -}}
{{- $ := . -}}
- name: BLUEECONOMY_STORAGE_BACKEND
  value: {{ .Values.storage.backend | quote }}
- name: BLUEECONOMY_STORAGE_ACCOUNT
  value: {{ .Values.storage.account | quote }}
- name: BLUEECONOMY_STORAGE_FILESYSTEM
  value: {{ .Values.storage.filesystem | quote }}
- name: KEY_DIRECTORY_PATH
  value: {{ .Values.keyDirectory.mountPath | quote }}
{{- range $key := (default (list) .Values.secretEnv) }}
- name: {{ $key | quote }}
  valueFrom:
    secretKeyRef:
      name: {{ include "data-platform.secretName" $ | quote }}
      key: {{ $key | quote }}
{{- end }}
{{- end -}}
