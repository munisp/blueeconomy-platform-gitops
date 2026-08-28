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
assert_default_render_fails_closed credential-verification 'credential-api.image.repository is required'
assert_default_render_fails_closed fisheries-traceability 'image.repository is required'
assert_default_render_fails_closed maritime-intelligence 'api.image.repository is required'
assert_default_render_fails_closed dapr-components 'workstream.name is required'
assert_default_render_fails_closed temporal 'temporal.image.digest is required'
assert_default_render_fails_closed keycloak-realms 'externalSecrets.storeRef.name is required'

# Positive render gates: every shared-platform chart must render fully with
# its CI render fixture (fail-closed defaults exercised separately above).
for chart in ferry-ticketing financial-controls port-interoperability security-operations \
  credential-verification fisheries-traceability maritime-intelligence \
  temporal keycloak-realms; do
  helm template render-gate "$repo_root/charts/$chart" \
    --kube-version "$helm_kube_version" \
    -f "$repo_root/ci/render-values/$chart.yaml" > /dev/null
done

# Dapr component layer: render every per-workstream fixture (the base cvff
# fixture plus the seafarer/fisheries/isr phase-2 fixtures).
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

printf '%s\n' 'Validated GitOps base manifests, workstream namespaces (ports/ferries/cvff with fiduciary segregation; seafarer/fisheries/isr with ISR national-security segregation), recovery namespace, upstream source locks (incl. Prometheus, OpenTelemetry Collector, Argo CD), chart sources, fail-closed value gates, shared-platform render fixtures (incl. phase-2 service charts and per-workstream Dapr fixtures), helm lint for every chart, Keycloak short-TTL, ISR clearance and CVFF/ISR scope gates, ISR outbox-mode and cold-chain breach-SLA gates, Kafka topic namespace prefixes, Argo CD project/ApplicationSet manifests, regional DR contract, Mojaloop security overrides and umbrella dependencies.'
