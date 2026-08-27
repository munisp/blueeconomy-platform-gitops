{{- define "keycloak-realms.labels" -}}
app.kubernetes.io/name: keycloak-realms
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end -}}

{{- define "keycloak-realms.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name "keycloak-realms" | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Build a realm JSON document. Client secrets deliberately use the
keycloak-config-cli "*********" sentinel (leave unchanged on re-import);
real secret material exists only in the external secret store.
*/}}
{{- define "keycloak-realms.realmJson" -}}
{{- $realm := index . "realm" -}}
{{- $policy := index . "policy" -}}
{{- $roles := list -}}
{{- range $r := $realm.roles -}}
{{- $roles = append $roles (dict "name" $r) -}}
{{- end -}}
{{- $clients := list -}}
{{- range $c := $realm.clients -}}
{{- $clients = append $clients (dict
  "clientId" $c.clientId
  "protocol" "openid-connect"
  "publicClient" false
  "serviceAccountsEnabled" true
  "standardFlowEnabled" false
  "directAccessGrantsEnabled" false
  "secret" "*********"
  "attributes" (dict "client.secret.creation.time" "0")
) -}}
{{- end -}}
{{- dict
  "realm" $realm.name
  "enabled" true
  "sslRequired" "external"
  "registrationAllowed" false
  "verifyEmail" false
  "resetPasswordAllowed" false
  "bruteForceProtected" true
  "accessTokenLifespan" (int $policy.accessTokenLifespan)
  "accessCodeLifespan" (int $policy.accessCodeLifespan)
  "ssoSessionIdleTimeout" (int $policy.ssoSessionIdleTimeout)
  "ssoSessionMaxLifespan" (int $policy.ssoSessionMaxLifespan)
  "roles" (dict "realm" $roles)
  "clients" $clients
| toPrettyJson -}}
{{- end -}}
