{{- define "beneficiary-portal.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "beneficiary-portal.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "beneficiary-portal.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "beneficiary-portal.labels" -}}
app.kubernetes.io/name: {{ include "beneficiary-portal.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
blueeconomy.platform/workstream: {{ .Values.workstream | quote }}
{{- end -}}

{{- define "beneficiary-portal.selectorLabels" -}}
app.kubernetes.io/name: {{ include "beneficiary-portal.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "beneficiary-portal.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "beneficiary-portal.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- required "serviceAccount.name is required when serviceAccount.create=false" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Runtime configuration served to the browser at /platform-config.json
(schema: src/runtime-config.ts in blueeconomy-beneficiary-portal). Public
discovery metadata only; no secret material may ever appear here.
*/}}
{{- define "beneficiary-portal.platformConfigJson" -}}
{{- $oidc := .Values.platformConfig.oidc -}}
{{- $api := .Values.platformConfig.cvffApi -}}
{{- $oidcDoc := dict
  "authority" $oidc.authority
  "client_id" $oidc.clientId
  "redirect_uri" $oidc.redirectUri
  "scope" $oidc.scope
-}}
{{- if $oidc.postLogoutRedirectUri -}}
{{- $_ := set $oidcDoc "post_logout_redirect_uri" $oidc.postLogoutRedirectUri -}}
{{- end -}}
{{- dict
  "application_name" .Values.platformConfig.applicationName
  "oidc" $oidcDoc
  "cvff_api" (dict
    "base_url" $api.baseUrl
    "poll_interval_ms" (int $api.pollIntervalMs)
    "max_document_bytes" (int $api.maxDocumentBytes)
    "document_content_types" $api.documentContentTypes
  )
| toPrettyJson -}}
{{- end -}}
