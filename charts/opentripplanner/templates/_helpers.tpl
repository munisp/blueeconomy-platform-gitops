{{- define "opentripplanner.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "opentripplanner.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "opentripplanner.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "opentripplanner.labels" -}}
app.kubernetes.io/name: {{ include "opentripplanner.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end -}}

{{- define "opentripplanner.selectorLabels" -}}
app.kubernetes.io/name: {{ include "opentripplanner.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "opentripplanner.secretName" -}}
{{- printf "%s-env" (include "opentripplanner.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "opentripplanner.pvcName" -}}
{{- if .Values.persistence.existingClaim -}}
{{- .Values.persistence.existingClaim -}}
{{- else -}}
{{- printf "%s-graph" (include "opentripplanner.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Graph volume source for the serve pods: shared PVC, or a per-pod
    emptyDir when graph.url fetch is configured. */}}
{{- define "opentripplanner.graphVolume" -}}
{{- if and (eq .Values.mode "serve") .Values.graph.url -}}
emptyDir: {}
{{- else -}}
persistentVolumeClaim:
  claimName: {{ include "opentripplanner.pvcName" . }}
{{- end -}}
{{- end -}}
