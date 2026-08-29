{{- define "ministry-portal.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "ministry-portal.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "ministry-portal.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "ministry-portal.labels" -}}
app.kubernetes.io/name: {{ include "ministry-portal.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
blueeconomy.platform/workstream: {{ .Values.workstream | quote }}
{{- end -}}

{{- define "ministry-portal.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ministry-portal.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "ministry-portal.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "ministry-portal.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- required "serviceAccount.name is required when serviceAccount.create=false" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Runtime configuration served to the browser at /platform-config.json
(schema: src/runtime-config.ts in blueeconomy-ministry-portal). Public
discovery metadata only; no secret material may ever appear here.
*/}}
{{- define "ministry-portal.platformConfigJson" -}}
{{- $oidc := .Values.platformConfig.oidc -}}
{{- $admin := .Values.platformConfig.administration -}}
{{- $oidcDoc := dict
  "authority" $oidc.authority
  "client_id" $oidc.clientId
  "redirect_uri" $oidc.redirectUri
  "scope" $oidc.scope
-}}
{{- if $oidc.postLogoutRedirectUri -}}
{{- $_ := set $oidcDoc "post_logout_redirect_uri" $oidc.postLogoutRedirectUri -}}
{{- end -}}
{{- $services := list -}}
{{- range $svc := .Values.platformConfig.services -}}
{{- $services = append $services (dict
  "id" $svc.id
  "label" $svc.label
  "health_url" $svc.healthUrl
  "required_roles" $svc.requiredRoles
) -}}
{{- end -}}
{{- $doc := dict
  "application_name" .Values.platformConfig.applicationName
  "oidc" $oidcDoc
  "administration" (dict
    "onboarding_api_url" $admin.onboardingApiUrl
    "organization_id" $admin.organizationId
    "allowed_roles" $admin.allowedRoles
  )
  "services" $services
-}}
{{- if .Values.platformConfig.geospatial.enabled -}}
{{- $geo := .Values.platformConfig.geospatial -}}
{{- $geoDoc := dict
  "geo_api_url" $geo.geoApiUrl
  "tile_url" $geo.tileUrl
  "poll_interval_ms" (int $geo.pollIntervalMs)
  "geolibre_enabled" (eq true $geo.geolibreEnabled)
-}}
{{- if $geo.tileAttribution -}}
{{- $_ := set $geoDoc "tile_attribution" $geo.tileAttribution -}}
{{- end -}}
{{- if $geo.cesiumBaseUrl -}}
{{- $_ := set $geoDoc "cesium_base_url" $geo.cesiumBaseUrl -}}
{{- end -}}
{{- if $geo.geolibreUrl -}}
{{- $_ := set $geoDoc "geolibre_url" $geo.geolibreUrl -}}
{{- end -}}
{{- $_ := set $doc "geospatial" $geoDoc -}}
{{- end -}}
{{- $doc | toPrettyJson -}}
{{- end -}}
