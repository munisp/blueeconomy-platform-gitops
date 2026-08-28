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
{{- $clearance := dig "clearanceScope" "enabled" false $realm -}}
{{- $clients := list -}}
{{- range $c := $realm.clients -}}
{{- $client := dict
  "clientId" $c.clientId
  "protocol" "openid-connect"
  "publicClient" false
  "serviceAccountsEnabled" true
  "standardFlowEnabled" false
  "directAccessGrantsEnabled" false
  "secret" "*********"
  "attributes" (dict "client.secret.creation.time" "0")
-}}
{{- if $clearance -}}
{{- $_ := set $client "defaultClientScopes" (list "clearance") -}}
{{- end -}}
{{- $clients = append $clients $client -}}
{{- end -}}
{{- $doc := dict
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
-}}
{{- if $clearance -}}
{{- /* Clearance discipline: the user attribute is admin-managed only (no
       self-service), option-validated against the approved label set, and
       mapped to the access-token "clearance" claim by the clearance client
       scope. Labels only; no classified data in this repository. */ -}}
{{- $_ := set $doc "userProfile" (dict "attributes" (list (dict
  "name" "clearance"
  "displayName" "Security clearance"
  "required" (dict "roles" (list "admin"))
  "permissions" (dict "view" (list "admin") "edit" (list "admin"))
  "validations" (dict "options" (dict "options" $realm.clearanceScope.levels))
))) -}}
{{- $_ := set $doc "clientScopes" (list (dict
  "name" "clearance"
  "protocol" "openid-connect"
  "attributes" (dict "include.in.token.scope" "true" "display.on.consent.screen" "false")
  "protocolMappers" (list (dict
    "name" "clearance"
    "protocol" "openid-connect"
    "protocolMapper" "oidc-usermodel-attribute-mapper"
    "config" (dict
      "user.attribute" "clearance"
      "claim.name" "clearance"
      "jsonType.label" "String"
      "id.token.claim" "false"
      "access.token.claim" "true"
      "userinfo.token.claim" "true")
  ))
)) -}}
{{- end -}}
{{- $doc | toPrettyJson -}}
{{- end -}}
