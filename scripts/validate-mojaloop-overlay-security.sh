#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helm_kube_version="${HELM_KUBE_VERSION:-1.28.0}"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
values="$workspace/mojaloop-local-contract.yaml"

cat > "$values" <<'YAML'
# Local manifest-validation fixture only. It contains no credential, certificate,
# participant, payment, settlement or Ministry environment identifier.
upstream:
  chartName: local-validation-upstream
  chartVersion: 0.0.0-local
  repository: https://charts.example.invalid/local-validation
identity:
  keycloak:
    issuerURL: https://issuer.example.invalid/realms/local-validation
    jwksURI: https://issuer.example.invalid/realms/local-validation/protocol/openid-connect/certs
    assertions:
      requireIssuerExactMatch: true
      requireJWKSValidation: true
      requireExpiry: true
      requireNotBefore: true
      maximumClockSkewSeconds: 60
      allowedSigningAlgorithms: [RS256]
    clientSecretRef:
      name: local-keycloak-reference
      key: client-secret
  mTLS:
    certificateSecretRef:
      name: local-mtls-reference
      key: tls.crt
    trustedCASecretRef:
      name: local-mtls-ca-reference
      key: ca.crt
backingServices:
  mysql:
    host: mysql.example.invalid
    secretRef: local-mysql-reference
  redis:
    host: redis.example.invalid
    secretRef: local-redis-reference
apiGateway:
  attachment:
    pluginSetReference: local-apisix-plugin-set-v1
    pluginSetSHA256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    policyChangeApprovalRef: local-apisix-policy-change-v1
  partnerRoutes:
    - name: local-partner
      hostname: partner.example.invalid
      pathPrefix: /payments/v1
      allowedMethods: [GET, POST]
      rateLimitPolicy: local-rate-policy
      audience: local-partner-audience
      scopes: ["payments.read"]
      requireMTLS: true
      schemaProfile: local-partner-schema-v1
operations:
  auditExport:
    kafkaTopic: local-audit-topic
  settlementAuthority: local-settlement-authority
YAML

render() {
  helm template mojaloop-security "$repo_root/charts/mojaloop-overlay" \
    --namespace blueeco-mojaloop-local-validation \
    --kube-version "$helm_kube_version" \
    --values "$values" "$@"
}

render > "$workspace/rendered.yaml"
grep -q 'kind: ConfigMap' "$workspace/rendered.yaml"
if grep -q 'kind: Secret' "$workspace/rendered.yaml"; then
  echo 'Mojaloop overlay must not render plaintext Secret resources' >&2
  exit 1
fi

assert_override_fails() {
  local expected="$1"
  shift
  local output
  output="$(mktemp)"
  if render "$@" > /dev/null 2>"$output"; then
    echo "Mojaloop overlay accepted insecure override: $*" >&2
    rm -f "$output"
    exit 1
  fi
  if ! grep -Fq "$expected" "$output"; then
    cat "$output" >&2
    echo "Mojaloop overlay did not emit expected guard: $expected" >&2
    rm -f "$output"
    exit 1
  fi
  rm -f "$output"
}

assert_override_fails 'identity.keycloak.enabled must remain true' --set identity.keycloak.enabled=false
assert_override_fails 'identity.keycloak.issuerURL must be an HTTPS issuer URL' --set identity.keycloak.issuerURL=http://issuer.example.invalid/realm
assert_override_fails 'identity.keycloak.jwksURI must be an HTTPS JWKS URL' --set identity.keycloak.jwksURI=http://issuer.example.invalid/certs
assert_override_fails 'identity.keycloak.assertions.requireExpiry must remain true' --set identity.keycloak.assertions.requireExpiry=false
assert_override_fails 'identity.keycloak.assertions.maximumClockSkewSeconds must be between 0 and 120' --set identity.keycloak.assertions.maximumClockSkewSeconds=121
assert_override_fails 'identity.keycloak.assertions.allowedSigningAlgorithms[0] must be RS256, PS256 or ES256' --set-json 'identity.keycloak.assertions.allowedSigningAlgorithms=["HS256"]'
assert_override_fails 'identity.mTLS.enabled must remain true' --set identity.mTLS.enabled=false
assert_override_fails 'identity.mTLS.trustedCASecretRef.name must contain an approved non-placeholder value' --set identity.mTLS.trustedCASecretRef.name=
assert_override_fails 'secrets.provider must be external-secrets' --set secrets.provider=plaintext
assert_override_fails 'namespacePolicy.enforcePrivateAdministration must remain true' --set namespacePolicy.enforcePrivateAdministration=false
assert_override_fails 'namespacePolicy.permittedIngressController must be apisix' --set namespacePolicy.permittedIngressController=nginx
assert_override_fails 'namespacePolicy.requireNetworkPolicies must remain true' --set namespacePolicy.requireNetworkPolicies=false
assert_override_fails 'namespacePolicy.requirePodSecurityStandard must remain restricted' --set namespacePolicy.requirePodSecurityStandard=baseline
assert_override_fails 'upstream.imagePolicy.requireDigestPinning must remain true' --set upstream.imagePolicy.requireDigestPinning=false
assert_override_fails 'upstream.imagePolicy.requireSignedArtifacts must remain true' --set upstream.imagePolicy.requireSignedArtifacts=false
assert_override_fails 'upstream.imagePolicy.requireSBOM must remain true' --set upstream.imagePolicy.requireSBOM=false
assert_override_fails 'backingServices.mysql.mode must be external-managed' --set backingServices.mysql.mode=embedded
assert_override_fails 'backingServices.redis.mode must be external-managed' --set backingServices.redis.mode=embedded
assert_override_fails 'apiGateway.adminRoutesPrivate must remain true' --set apiGateway.adminRoutesPrivate=false
assert_override_fails 'apiGateway.attachment.pluginSetReference must contain an approved non-placeholder value' --set apiGateway.attachment.pluginSetReference=
assert_override_fails 'apiGateway.attachment.pluginSetSHA256 must be a 64-character SHA-256 digest' --set apiGateway.attachment.pluginSetSHA256=not-a-digest
assert_override_fails 'apiGateway.attachment.policyChangeApprovalRef must contain an approved non-placeholder value' --set apiGateway.attachment.policyChangeApprovalRef=
assert_override_fails 'apiGateway.partnerRoutes must contain at least one approved partner route' --set-json 'apiGateway.partnerRoutes=[]'
assert_override_fails 'apiGateway.requireOIDCAudienceValidation must remain true' --set apiGateway.requireOIDCAudienceValidation=false
assert_override_fails 'apiGateway.requireOIDCScopeValidation must remain true' --set apiGateway.requireOIDCScopeValidation=false
assert_override_fails 'apiGateway.requireTLS12Minimum must remain true' --set apiGateway.requireTLS12Minimum=false
assert_override_fails 'apiGateway.rejectBearerTokenQueryParameters must remain true' --set apiGateway.rejectBearerTokenQueryParameters=false
assert_override_fails 'apiGateway.partnerRoutes[0].requireMTLS must remain true' --set apiGateway.partnerRoutes[0].requireMTLS=false
assert_override_fails 'apiGateway.partnerRoutes[0].name must be a canonical route identifier' --set apiGateway.partnerRoutes[0].name=local/partner
assert_override_fails 'apiGateway.partnerRoutes[0].hostname must be a DNS hostname' --set apiGateway.partnerRoutes[0].hostname=bad_host
assert_override_fails 'apiGateway.partnerRoutes[0].hostname must be lowercase' --set apiGateway.partnerRoutes[0].hostname=Partner.example.invalid
assert_override_fails 'apiGateway.partnerRoutes[0].scopes must not contain duplicates' --set-json 'apiGateway.partnerRoutes[0].scopes=["payments.read","payments.read"]'
assert_override_fails 'apiGateway.partnerRoutes[0].scopes[0] must be a canonical scope identifier' --set-json 'apiGateway.partnerRoutes[0].scopes=["payments read"]'
assert_override_fails 'apiGateway.partnerRoutes[0].audience must contain an approved non-placeholder value' --set apiGateway.partnerRoutes[0].audience=
assert_override_fails 'apiGateway.partnerRoutes[0].scopes must contain at least one approved scope' --set-json 'apiGateway.partnerRoutes[0].scopes=[]'
assert_override_fails 'apiGateway.partnerRoutes[0].schemaProfile must contain an approved non-placeholder value' --set apiGateway.partnerRoutes[0].schemaProfile=
assert_override_fails 'apiGateway.partnerRoutes[0].pathPrefix must contain an approved non-placeholder value' --set apiGateway.partnerRoutes[0].pathPrefix=
assert_override_fails 'apiGateway.partnerRoutes[0].pathPrefix must be an absolute path without traversal' --set apiGateway.partnerRoutes[0].pathPrefix=relative
assert_override_fails 'apiGateway.partnerRoutes[0].allowedMethods must contain at least one approved method' --set-json 'apiGateway.partnerRoutes[0].allowedMethods=[]'
assert_override_fails 'apiGateway.partnerRoutes[0].allowedMethods[0] must be GET, POST, PUT, PATCH or DELETE' --set-json 'apiGateway.partnerRoutes[0].allowedMethods=["TRACE"]'
assert_override_fails 'apiGateway.partnerRoutes[0].allowedMethods must not contain duplicates' --set-json 'apiGateway.partnerRoutes[0].allowedMethods=["GET","GET"]'
assert_override_fails 'apiGateway.partnerRoutes[1] duplicates hostname and pathPrefix of another route' --set-json 'apiGateway.partnerRoutes=[{"name":"local-partner","hostname":"partner.example.invalid","pathPrefix":"/payments/v1","allowedMethods":["GET"],"rateLimitPolicy":"local-rate-policy","audience":"local-partner-audience","scopes":["payments.read"],"requireMTLS":true,"schemaProfile":"local-partner-schema-v1"},{"name":"second-partner","hostname":"partner.example.invalid","pathPrefix":"/payments/v1","allowedMethods":["POST"],"rateLimitPolicy":"second-rate-policy","audience":"second-partner-audience","scopes":["payments.write"],"requireMTLS":true,"schemaProfile":"second-partner-schema-v1"}]'
assert_override_fails 'apiGateway.requireCorrelationID must remain true' --set apiGateway.requireCorrelationID=false
assert_override_fails 'apiGateway.requireSchemaValidation must remain true' --set apiGateway.requireSchemaValidation=false
assert_override_fails 'apiGateway.requireOpenAppSec must remain true' --set apiGateway.requireOpenAppSec=false
assert_override_fails 'operations.auditExport.enabled must remain true' --set operations.auditExport.enabled=false
assert_override_fails 'operations.backup.required must remain true' --set operations.backup.required=false
assert_override_fails 'operations.dailyReconciliation.required must remain true' --set operations.dailyReconciliation.required=false

printf '%s\n' 'Validated Mojaloop Keycloak, mTLS, APISIX attachment-contract, partner-route and regulated-operation fail-closed render guards.'
