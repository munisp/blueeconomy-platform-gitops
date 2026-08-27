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

# Shared-platform namespaces: each must ship a Namespace plus a default-deny
# NetworkPolicy; cvff additionally requires the cross-workstream ingress denial.
for ns in ports ferries cvff; do
  grep -q 'kind: Namespace' "$repo_root/kubernetes/base/namespaces/$ns.yaml"
  grep -q 'kind: NetworkPolicy' "$repo_root/kubernetes/base/namespaces/$ns.yaml"
done
grep -q 'deny-cross-workstream-ingress' "$repo_root/kubernetes/base/namespaces/cvff.yaml"
grep -q 'fiduciary-segregated' "$repo_root/kubernetes/base/namespaces/cvff.yaml"

for chart in tigerbeetle mojaloop-overlay sedona-spark-jobs core-services regional-dr \
  ferry-ticketing financial-controls port-interoperability security-operations \
  dapr-components temporal keycloak-realms; do
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
assert_default_render_fails_closed financial-controls 'cvff-worker.image.repository is required'
assert_default_render_fails_closed port-interoperability 'api.image.repository is required'
assert_default_render_fails_closed security-operations 'detection-engine.image.repository is required'
assert_default_render_fails_closed dapr-components 'workstream.name is required'
assert_default_render_fails_closed temporal 'temporal.image.digest is required'
assert_default_render_fails_closed keycloak-realms 'externalSecrets.storeRef.name is required'

# Positive render gates: every shared-platform chart must render fully with
# its CI render fixture (fail-closed defaults exercised separately above).
for chart in ferry-ticketing financial-controls port-interoperability security-operations \
  dapr-components temporal keycloak-realms; do
  helm template render-gate "$repo_root/charts/$chart" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/$chart.yaml" > /dev/null
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

printf '%s\n' 'Validated GitOps base manifests, workstream namespaces (ports/ferries/cvff with fiduciary segregation), recovery namespace, upstream source locks (incl. Prometheus, OpenTelemetry Collector, Argo CD), chart sources, fail-closed value gates, shared-platform render fixtures, Keycloak short-TTL and CVFF scope gates, Argo CD project/ApplicationSet manifests, regional DR contract, Mojaloop security overrides and umbrella dependencies.'
