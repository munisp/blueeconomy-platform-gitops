#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helm version --short >/dev/null
# Helm otherwise defaults to a legacy synthetic Kubernetes 1.20 capability. The
# charts declare Kubernetes 1.28+ support; test that baseline explicitly while
# allowing approved CI or target pipelines to provide their exact capability.
helm_kube_version="${HELM_KUBE_VERSION:-1.28.0}"

# The base uses Kustomize, so validate the required namespace and default-deny sources directly.
grep -q 'kind: Namespace' "$repo_root/kubernetes/base/namespaces/platform.yaml"
grep -q 'kind: NetworkPolicy' "$repo_root/kubernetes/base/namespaces/platform.yaml"
grep -q 'kind: Namespace' "$repo_root/kubernetes/base/namespaces/security.yaml"
grep -q 'kind: NetworkPolicy' "$repo_root/kubernetes/base/namespaces/security.yaml"

lockfile="$repo_root/components/upstream-components.lock.yaml"
test -s "$lockfile"
grep -q 'deployment_status: source_locked_not_deployed' "$lockfile"
grep -q 'apache-apisix' "$lockfile"
grep -q 'keycloak-operator' "$lockfile"
grep -q 'wazuh-kubernetes' "$lockfile"
grep -q 'strimzi-kafka-operator' "$lockfile"
grep -q 'temporal' "$lockfile"
grep -q 'dapr' "$lockfile"
grep -q 'cloudnative-pg' "$lockfile"
grep -q 'prometheus' "$lockfile"
grep -q 'opentelemetry-collector' "$lockfile"
grep -q 'argo-cd' "$lockfile"
sha_count="$(grep -E 'artifact_sha256: [0-9a-f]{64}$' "$lockfile" | wc -l)"
test "$sha_count" -ge 9
# Gap #41 hash-locks: cilium/velero chart artifact hashes and caddy/opa
# image digests must be present and well-formed.
grep -q 'chart: cilium/cilium' "$lockfile"
grep -q 'chart: vmware-tanzu/velero' "$lockfile"
grep -q 'image: library/caddy' "$lockfile"
grep -q 'image: openpolicyagent/opa' "$lockfile"
digest_count="$(grep -cE 'digest: sha256:[0-9a-f]{64}$' "$lockfile")"
test "$digest_count" -ge 2

# Shared-platform namespaces: each must ship a Namespace plus a default-deny
# NetworkPolicy; cvff additionally requires the cross-workstream ingress denial.
for ns in ports ferries cvff seafarer fisheries isr; do
  grep -q 'kind: Namespace' "$repo_root/kubernetes/base/namespaces/$ns.yaml"
  grep -q 'kind: NetworkPolicy' "$repo_root/kubernetes/base/namespaces/$ns.yaml"
done
grep -q 'deny-cross-workstream-ingress' "$repo_root/kubernetes/base/namespaces/cvff.yaml"
grep -q 'fiduciary-segregated' "$repo_root/kubernetes/base/namespaces/cvff.yaml"
# ISR namespace: same cross-workstream segregation as cvff, plus the
# national-security-controlled classification label and restricted PSA.
grep -q 'deny-cross-workstream-ingress' "$repo_root/kubernetes/base/namespaces/isr.yaml"
grep -q 'national-security-controlled' "$repo_root/kubernetes/base/namespaces/isr.yaml"
grep -q 'pod-security.kubernetes.io/enforce: restricted' "$repo_root/kubernetes/base/namespaces/isr.yaml"

for chart in tigerbeetle mojaloop-overlay sedona-spark-jobs core-services regional-dr \
  ferry-ticketing financial-controls port-interoperability security-operations \
  credential-verification fisheries-traceability maritime-intelligence \
  dapr-components temporal keycloak-realms beneficiary-portal ministry-portal \
  administration-service \
  cilium caddy opa-policies backup-dr \
  postgis martin geo-service apisix-routes; do
  test -s "$repo_root/charts/$chart/Chart.yaml"
  test -s "$repo_root/charts/$chart/values.yaml"
done

if find "$repo_root/charts" -type f \( -name 'values.yaml' -o -name 'Chart.yaml' \) -print0 | \
  xargs -0 grep -nE 'REPLACE_WITH|REQUIRED_APPROVED|REQUIRED_COMPATIBLE'; then
  echo 'chart metadata or deployable default values contain a prohibited placeholder token' >&2
  exit 1
fi

assert_default_render_fails_closed() {
  local chart="$1"
  local expected="$2"
  local output
  output="$(mktemp)"
  if helm template validation "$repo_root/charts/$chart" --kube-version "$helm_kube_version" > /dev/null 2>"$output"; then
    echo "$chart rendered without approved environment values" >&2
    rm -f "$output"
    exit 1
  fi
  if ! grep -Fq "$expected" "$output"; then
    cat "$output" >&2
    echo "$chart did not fail with its expected approval gate" >&2
    rm -f "$output"
    exit 1
  fi
  rm -f "$output"
}

assert_default_render_fails_closed tigerbeetle 'tigerbeetle.clusterID is required'
assert_default_render_fails_closed mojaloop-overlay 'upstream.chartName must be set'
assert_default_render_fails_closed sedona-spark-jobs 'spark.sparkVersion is required'
assert_default_render_fails_closed regional-dr 'regionalDR.primary.region'
assert_default_render_fails_closed ferry-ticketing 'ferry-api.image.repository is required'
# financial-controls: components render in alphabetical order, so the first
# approval gate hit without environment values is cvff-api.
assert_default_render_fails_closed financial-controls 'cvff-api.image.repository is required'
assert_default_render_fails_closed port-interoperability 'api.image.repository is required'
assert_default_render_fails_closed security-operations 'detection-engine.image.repository is required'
assert_default_render_fails_closed credential-verification 'credential-api.image.repository is required'
assert_default_render_fails_closed fisheries-traceability 'image.repository is required'
assert_default_render_fails_closed maritime-intelligence 'api.image.repository is required'
assert_default_render_fails_closed dapr-components 'workstream.name is required'
assert_default_render_fails_closed temporal 'temporal.image.digest is required'
assert_default_render_fails_closed keycloak-realms 'externalSecrets.storeRef.name is required'
assert_default_render_fails_closed beneficiary-portal 'image.repository is required'
assert_default_render_fails_closed ministry-portal 'image.repository is required'
assert_default_render_fails_closed administration-service 'image.repository is required'
assert_default_render_fails_closed cilium 'cilium upstream.chartName is required'
assert_default_render_fails_closed caddy 'image.digest is required'
assert_default_render_fails_closed opa-policies 'opa.image.digest is required'
assert_default_render_fails_closed backup-dr 'backup-dr upstream.chartName is required'
assert_default_render_fails_closed postgis 'image.variant must be one of: cloudnative-pg, postgis-image'
assert_default_render_fails_closed martin 'image.repository is required'
assert_default_render_fails_closed geo-service 'profile must be one of: dev, staging, prod'
assert_default_render_fails_closed apisix-routes 'apisix.enabled must be true'

# Positive render gates: every shared-platform chart must render fully with
# its CI render fixture (fail-closed defaults exercised separately above).
for chart in ferry-ticketing financial-controls port-interoperability security-operations \
  credential-verification fisheries-traceability maritime-intelligence \
  temporal keycloak-realms beneficiary-portal ministry-portal \
  administration-service \
  cilium opa-policies sedona-spark-jobs martin geo-service apisix-routes; do
  helm template render-gate "$repo_root/charts/$chart" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/$chart.yaml" > /dev/null
done

# Edge TLS provider families (cloud-agnostic contract): render every
# per-provider caddy fixture — rfc2136 (provider-neutral default),
# azuredns, internal-ca and manual.
for fixture in "$repo_root"/ci/render-values/caddy*.yaml; do
  helm template render-gate "$repo_root/charts/caddy" \
    --kube-version "$helm_kube_version" \
    -f "$fixture" > /dev/null
done

# Backup storage provider families: render both backup-dr fixtures
# (s3-compatible provider-neutral and azure landing-zone option).
for fixture in "$repo_root"/ci/render-values/backup-dr*.yaml; do
  helm template render-gate "$repo_root/charts/backup-dr" \
    --kube-version "$helm_kube_version" \
    -f "$fixture" > /dev/null
done

# PostGIS image-variant families (cloud-agnostic render-gated enum): render
# both the cloudnative-pg operand and the postgis-image StatefulSet fixture.
for fixture in "$repo_root"/ci/render-values/postgis*.yaml; do
  helm template render-gate "$repo_root/charts/postgis" \
    --kube-version "$helm_kube_version" \
    -f "$fixture" > /dev/null
done

# Dapr component layer: render every per-workstream fixture (the base cvff
# fixture plus the ports/ferries and seafarer/fisheries/isr phase-2 fixtures).
for fixture in "$repo_root"/ci/render-values/dapr-components*.yaml; do
  helm template render-gate "$repo_root/charts/dapr-components" \
    --kube-version "$helm_kube_version" \
    -f "$fixture" > /dev/null
done

# helm lint every chart. Fail-closed default values lint clean for all
# charts except the two covered by their own dedicated gates below:
# regional-dr (JSON-schema approval gate, exercised by
# validate-regional-dr.sh) and core-services (umbrella chart requiring a
# dependency build, linted after helm dependency build at the end of this
# script).
for chart_dir in "$repo_root"/charts/*/; do
  chart_name="$(basename "$chart_dir")"
  case "$chart_name" in
    regional-dr|core-services) continue ;;
  esac
  helm lint "$chart_dir" --kube-version "$helm_kube_version" > /dev/null
done

# Short-TTL token policy gate: access token lifespans above 300s are rejected.
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/keycloak-realms" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/keycloak-realms.yaml" \
    --set tokenPolicy.accessTokenLifespan=600 > /dev/null 2>"$output"; then
  echo 'keycloak-realms rendered with an access token lifespan above 300s' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq '300 seconds or less' "$output"
rm -f "$output"

# CVFF fiduciary segregation gate: widening cvff Dapr component scopes to a
# non-cvff app-id is rejected at render time.
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/dapr-components" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/dapr-components.yaml" \
    --set 'workstream.appIds[0]=ferry-api' > /dev/null 2>"$output"; then
  echo 'dapr-components rendered a cvff release scoped to a non-cvff app-id' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'not a cvff app-id' "$output"
rm -f "$output"

# ISR national-security segregation gate: widening isr Dapr component scopes
# to a non-isr app-id is rejected at render time.
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/dapr-components" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/dapr-components-isr.yaml" \
    --set 'workstream.appIds[0]=ferry-api' > /dev/null 2>"$output"; then
  echo 'dapr-components rendered an isr release scoped to a non-isr app-id' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'not an isr app-id' "$output"
rm -f "$output"

# Scope segregation gates for the remaining workstreams: widening ports,
# ferries, seafarer or fisheries Dapr component scopes to a foreign app-id
# is rejected at render time, exactly like the cvff/isr gates above.
for ws in ports ferries seafarer fisheries; do
  output="$(mktemp)"
  if helm template render-gate "$repo_root/charts/dapr-components" \
      --kube-version "$helm_kube_version" \
      -f "$repo_root/ci/render-values/dapr-components-$ws.yaml" \
      --set 'workstream.appIds[0]=ferry-api' > /dev/null 2>"$output"; then
    if [ "$ws" = ferries ]; then
      # ferry-api is a valid ferries app-id; widen with a foreign one instead.
      rm -f "$output"
      output="$(mktemp)"
      if helm template render-gate "$repo_root/charts/dapr-components" \
          --kube-version "$helm_kube_version" \
          -f "$repo_root/ci/render-values/dapr-components-$ws.yaml" \
          --set 'workstream.appIds[0]=intent-api' > /dev/null 2>"$output"; then
        echo "dapr-components rendered a $ws release scoped to a non-$ws app-id" >&2
        rm -f "$output"
        exit 1
      fi
    else
      echo "dapr-components rendered a $ws release scoped to a non-$ws app-id" >&2
      rm -f "$output"
      exit 1
    fi
  fi
  grep -Fq "not a $ws app-id" "$output"
  rm -f "$output"
done

# ISR clearance gate: removing the classification clearance user attribute /
# client scope from the blueeconomy-isr realm is rejected at render time.
isr_no_clearance="$(mktemp)"
cat > "$isr_no_clearance" <<'EOF'
realms:
  - name: blueeconomy-isr
    workstreamNamespace: blueeconomy-isr
    roles:
      - nimasa-officer
    clearanceScope:
      enabled: false
    clients:
      - clientId: maritime-intelligence-api
EOF
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/keycloak-realms" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/keycloak-realms.yaml" \
    -f "$isr_no_clearance" > /dev/null 2>"$output"; then
  echo 'keycloak-realms rendered the isr realm without the clearance scope' >&2
  rm -f "$output" "$isr_no_clearance"
  exit 1
fi
grep -Fq 'clearanceScope.enabled=true' "$output"
rm -f "$output" "$isr_no_clearance"

# ISR outbox-mode gate: the maritime-intelligence release must stay in
# OUTBOX_SOURCE=isr mode with no fixed KAFKA_TOPIC (topics come from outbox
# rows, maritime.isr.* prefix).
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/maritime-intelligence" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/maritime-intelligence.yaml" \
    --set 'components.outbox-publisher.env.KAFKA_TOPIC=maritime.isr.v1' > /dev/null 2>"$output"; then
  echo 'maritime-intelligence rendered with a fixed KAFKA_TOPIC in isr mode' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'KAFKA_TOPIC must be unset in isr mode' "$output"
rm -f "$output"

# Cold-chain breach-alert KPI gate: breach SLAs above the approved 60-second
# platform KPI are rejected at render time.
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/fisheries-traceability" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/fisheries-traceability.yaml" \
    --set 'components.trace-api.env.FISHERIES_BREACH_ALERT_SLA_SECONDS=120' > /dev/null 2>"$output"; then
  echo 'fisheries-traceability rendered with a breach-alert SLA above the 60s platform KPI' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq '60 seconds or less' "$output"
rm -f "$output"

# Cilium fiduciary segregation gate: TigerBeetle egress may only exist in the
# cvff workstream policy; any other workstream declaring tigerbeetleAccess is
# rejected at render time.
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/cilium" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/cilium.yaml" \
    --set 'networkPolicies.workstreams[0].tigerbeetleAccess=true' > /dev/null 2>"$output"; then
  echo 'cilium rendered a non-cvff workstream with TigerBeetle egress' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'fiduciary segregation' "$output"
rm -f "$output"

# Cilium kernel baseline gate: node kernels below 5.4 are rejected at render
# time (kube-proxy replacement and XDP require >= 5.4).
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/cilium" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/cilium.yaml" \
    --set 'kernel.minVersion=4.19' > /dev/null 2>"$output"; then
  echo 'cilium rendered with a kernel baseline below 5.4' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'kernel.minVersion' "$output"
rm -f "$output"

# OpenAppSec contract-flag gate: disabling the WAF integration flag on the
# Caddy edge is rejected at render time (mirrors the mojaloop-overlay flag).
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/caddy" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/caddy.yaml" \
    --set 'openappsec.required=false' > /dev/null 2>"$output"; then
  echo 'caddy rendered with the OpenAppSec contract flag disabled' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'openappsec.required must remain true' "$output"
rm -f "$output"

# Producer key-directory gate: an opa-policies release missing any approved
# producer public key is rejected at render time.
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/opa-policies" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/opa-policies.yaml" \
    --set 'keyDirectory.publicKeys.waterway-safety-1=' > /dev/null 2>"$output"; then
  echo 'opa-policies rendered with a missing producer public key' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'keyDirectory.publicKeys.waterway-safety-1 is required' "$output"
rm -f "$output"

# DR immutability consistency gate: backup-dr immutabilityDays drifting from
# the regional-dr recovery contract is rejected at render time.
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/backup-dr" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/backup-dr.yaml" \
    --set 'backup.consistency.regionalDRImmutabilityDays=14' > /dev/null 2>"$output"; then
  echo 'backup-dr rendered with immutabilityDays not matching the regional-dr contract' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'must match the regional-dr contract' "$output"
rm -f "$output"

# Cloud-agnostic DNS/ACME provider gate: an unknown caddy issuance provider
# is rejected at render time (provider enum, never a hard Azure dependency).
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/caddy" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/caddy.yaml" \
    --set 'tls.acme.dnsProvider.name=bogus-provider' > /dev/null 2>"$output"; then
  echo 'caddy rendered with an unknown tls.acme.dnsProvider.name' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'must be one of: rfc2136, azuredns, route53, cloudflare, googleclouddns, digitalocean, internal-ca, manual' "$output"
rm -f "$output"

# rfc2136 fail-closed gate: the provider-neutral default refuses to render
# without its authoritative nameserver.
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/caddy" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/caddy.yaml" \
    --set 'tls.acme.dnsProvider.rfc2136.nameserver=' > /dev/null 2>"$output"; then
  echo 'caddy rendered provider=rfc2136 without a nameserver' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'rfc2136.nameserver is required' "$output"
rm -f "$output"

# rfc2136 TSIG gate: the TSIG secret reference is render-gated too.
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/caddy" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/caddy.yaml" \
    --set 'tls.acme.dnsProvider.rfc2136.tsigSecretRef.name=' > /dev/null 2>"$output"; then
  echo 'caddy rendered provider=rfc2136 without a TSIG secret ref' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'rfc2136.tsigSecretRef.name is required' "$output"
rm -f "$output"

# Backup storage provider gate: provider=s3-compatible without its generic
# endpoint is rejected at render time.
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/backup-dr" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/backup-dr.yaml" \
    --set 'storage.endpoint=' > /dev/null 2>"$output"; then
  echo 'backup-dr rendered provider=s3-compatible without storage.endpoint' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'storage.endpoint is required for provider=s3-compatible' "$output"
rm -f "$output"

# HashiCorp Vault secret-store gate: enabling the vault secret store without
# its server URL is rejected at render time.
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/dapr-components" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/dapr-components-vault.yaml" \
    --set 'secretStores.hashicorpVault.server=' > /dev/null 2>"$output"; then
  echo 'dapr-components rendered hashicorpVault without a server URL' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'hashicorpVault.server is required' "$output"
rm -f "$output"

# PostGIS image-enum gate: an unknown image.variant is rejected at render
# time (cloud-agnostic enum, never a hard operator dependency).
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/postgis" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/postgis.yaml" \
    --set 'image.variant=bogus-variant' > /dev/null 2>"$output"; then
  echo 'postgis rendered with an unknown image.variant' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'image.variant must be one of: cloudnative-pg, postgis-image' "$output"
rm -f "$output"

# PostGIS backup-provider gate: backup.storageProvider must stay within the
# backup-dr storage.provider enum.
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/postgis" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/postgis.yaml" \
    --set 'backup.storageProvider=gcs' > /dev/null 2>"$output"; then
  echo 'postgis rendered with backup.storageProvider outside the backup-dr enum' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'backup.storageProvider must be s3-compatible or azure' "$output"
rm -f "$output"

# Martin edge-registration gate: a Martin release without its registered
# APISIX edge route is rejected at render time (Martin has no auth).
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/martin" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/martin.yaml" \
    --set 'edge.routeRegistration.apisixRouteRef=' > /dev/null 2>"$output"; then
  echo 'martin rendered without its registered edge route' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'edge.routeRegistration.apisixRouteRef is required' "$output"
rm -f "$output"

# Martin no-auth contract gate: the route-registration requirement cannot
# be disabled.
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/martin" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/martin.yaml" \
    --set 'edge.routeRegistration.required=false' > /dev/null 2>"$output"; then
  echo 'martin rendered with the edge route-registration requirement disabled' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'edge.routeRegistration.required must remain true' "$output"
rm -f "$output"

# Geo-service prod-profile gate: GEO_TEST_* env names are refused in prod
# (no simulated feeds in production).
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/geo-service" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/geo-service.yaml" \
    --set 'env.GEO_TEST_FEED=enabled' > /dev/null 2>"$output"; then
  echo 'geo-service rendered a GEO_TEST_* env in the prod profile' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'is forbidden when profile=prod' "$output"
rm -f "$output"

# Signing unification gate (gap #40): mixing the provenance key into an
# envelope-convention release is rejected — exactly one convention per
# service (docs/signing-config.md).
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/geo-service" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/geo-service.yaml" \
    --set 'secretEnv[4]=PROVENANCE_SIGNING_KEY' \
    --set 'externalSecrets.keys.PROVENANCE_SIGNING_KEY=geo/render-fixture/provenance-key' > /dev/null 2>"$output"; then
  echo 'geo-service rendered with both signing conventions' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'exactly one signing convention per service' "$output"
rm -f "$output"

# Kafka TLS prod gate (gap #7): tls.required=true with tls.enabled=false is
# rejected at render time (service-side kafka env).
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/geo-service" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/geo-service.yaml" \
    --set 'kafka.tls.enabled=false' > /dev/null 2>"$output"; then
  echo 'geo-service rendered with kafka.tls.required=true but tls.enabled=false' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'kafka.tls.enabled must be true when kafka.tls.required=true' "$output"
rm -f "$output"

# APISIX route inventory gate (gap #49): a route without required Keycloak
# OIDC scopes is rejected at render time (bearer-only edge authn).
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/apisix-routes" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/apisix-routes.yaml" \
    --set 'routes[0].scopes=null' > /dev/null 2>"$output"; then
  echo 'apisix-routes rendered a route without required OIDC scopes' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'scopes must list the required Keycloak OIDC scopes' "$output"
rm -f "$output"

# Kafka TLS CA gate (gap #7): the Dapr pubsub component refuses TLS without
# its CA bundle secret reference.
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/dapr-components" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/dapr-components.yaml" \
    --set 'pubsub.kafka.tls.enabled=true' > /dev/null 2>"$output"; then
  echo 'dapr-components rendered kafka TLS without a caCertSecretRef' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'pubsub.kafka.tls.caCertSecretRef.name is required' "$output"
rm -f "$output"

# Kafka SASL plain-text gate (gap #7): SASL/PLAIN without TLS is rejected at
# render time.
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/dapr-components" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/dapr-components-kafka-tls.yaml" \
    --set 'pubsub.kafka.sasl.mechanism=plain' \
    --set 'pubsub.kafka.tls.enabled=false' \
    --set 'pubsub.kafka.tls.required=false' > /dev/null 2>"$output"; then
  echo 'dapr-components rendered SASL/PLAIN without TLS' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'mechanism=plain requires pubsub.kafka.tls.enabled=true' "$output"
rm -f "$output"

# Cilium geo-namespace gate: enabling the geo policies without the edge
# namespace is rejected at render time (edge-only ingress for geo-service
# and martin).
output="$(mktemp)"
if helm template render-gate "$repo_root/charts/cilium" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/cilium.yaml" \
    --set 'networkPolicies.geo.edgeNamespace=' > /dev/null 2>"$output"; then
  echo 'cilium rendered the geo policies without an edge namespace' >&2
  rm -f "$output"
  exit 1
fi
grep -Fq 'networkPolicies.geo.edgeNamespace is required' "$output"
rm -f "$output"

# Kafka topic namespace gate: every topic literal in the GitOps layer must
# use an approved workstream prefix, and each phase-2 scope (seafarer,
# fisheries, coldchain, export, maritime.isr) must be represented.
python3 - "$repo_root" <<'PYEOF'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
topic_re = re.compile(r"\b[a-z][a-z0-9]*(?:\.[a-z0-9]+)+\.v\d+\b")
approved = ("cvff.", "security.", "seafarer.", "fisheries.", "coldchain.", "export.", "maritime.isr.")
phase2 = ("seafarer.", "fisheries.", "coldchain.", "export.", "maritime.isr.")
topics = set()
for scope in ("charts", "ci", "kubernetes", "gitops"):
    for path in sorted((root / scope).rglob("*.yaml")):
        topics.update(topic_re.findall(path.read_text()))
violations = sorted(t for t in topics if not t.startswith(approved))
assert not violations, f"topic literals outside approved namespace prefixes: {violations}"
missing = [p for p in phase2 if not any(t.startswith(p) for t in topics)]
assert not missing, f"no topic literal found for phase-2 prefixes: {missing}"
PYEOF

# Argo CD manifests must be present, well-formed YAML of the expected kinds.
# ApplicationSet goTemplate directives are stripped before parsing.
python3 - "$repo_root/gitops/argocd" <<'PYEOF'
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
found = {}
for path in sorted(root.glob("*.yaml")):
    text = "\n".join(
        line for line in path.read_text().splitlines()
        if "{{" not in line and "}}" not in line
    )
    for doc in yaml.safe_load_all(text):
        if not doc:
            continue
        found.setdefault(doc["kind"], 0)
        found[doc["kind"]] += 1
for kind in ("AppProject", "ApplicationSet", "Application"):
    assert kind in found, f"missing Argo CD {kind} manifest"
PYEOF

workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
cp -a "$repo_root/charts" "$workspace/charts"
helm dependency build "$workspace/charts/core-services" >/dev/null
helm lint "$workspace/charts/core-services" --kube-version "$helm_kube_version" >/dev/null
helm template core-services "$workspace/charts/core-services" --kube-version "$helm_kube_version" >/dev/null
HELM_KUBE_VERSION="$helm_kube_version" bash "$repo_root/scripts/validate-mojaloop-overlay-security.sh"
HELM_KUBE_VERSION="$helm_kube_version" bash "$repo_root/scripts/validate-regional-dr.sh"

printf '%s\n' 'Validated GitOps base manifests, workstream namespaces (ports/ferries/cvff with fiduciary segregation; seafarer/fisheries/isr with ISR national-security segregation), core-service namespaces (tigerbeetle/mojaloop/geo), recovery namespace, upstream source locks (incl. Prometheus, OpenTelemetry Collector, Argo CD, and the gap-#41 hash-locked cilium/velero/caddy/opa pins), chart sources (incl. beneficiary-portal, the battle-hardened edge charts cilium/caddy/opa-policies/backup-dr and the geo deploy surface postgis/martin/geo-service/apisix-routes), fail-closed value gates, shared-platform render fixtures (incl. phase-2 service charts, beneficiary-portal, all six per-workstream Dapr fixtures plus the hashicorpVault/external secret-store and kafka-tls fixtures, all four caddy TLS provider fixtures, both backup-dr storage provider fixtures, both postgis image-variant fixtures and the sedona vessel-trajectory-silver fixture), helm lint for every chart, Keycloak short-TTL, PKCE public-client redirect allowlists, ISR clearance and all six workstream Dapr scope-segregation gates, ISR outbox-mode and cold-chain breach-SLA gates, Cilium fiduciary-segregation, kernel-baseline and geo-namespace gates, the Caddy OpenAppSec contract-flag gate, the OPA producer key-directory gate, the backup-dr immutability consistency gate, the cloud-agnostic provider gates (unknown DNS/ACME provider, rfc2136 nameserver/TSIG, s3-compatible endpoint, hashicorpVault server, postgis image enum and backup provider), the Martin edge route-registration gates, the geo-service prod-profile GEO_TEST_* gate, the signing unification gate (exactly one convention per service, docs/signing-config.md), the APISIX route-inventory gate, the Kafka TLS/SASL gates (caCert required, tls.required prod posture, SASL/PLAIN requires TLS), Kafka topic namespace prefixes (incl. geo.*), Argo CD project/ApplicationSet manifests, regional DR contract, Mojaloop security overrides and umbrella dependencies.'
