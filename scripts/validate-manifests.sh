#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helm version --short >/dev/null

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
sha_count="$(grep -E 'artifact_sha256: [0-9a-f]{64}$' "$lockfile" | wc -l)"
test "$sha_count" -ge 7

for chart in tigerbeetle mojaloop-overlay sedona-spark-jobs core-services; do
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
  if helm template validation "$repo_root/charts/$chart" > /dev/null 2>"$output"; then
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

workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
cp -a "$repo_root/charts" "$workspace/charts"
helm dependency build "$workspace/charts/core-services" >/dev/null
helm lint "$workspace/charts/core-services" >/dev/null
helm template core-services "$workspace/charts/core-services" >/dev/null

printf '%s\n' 'Validated GitOps base manifests, upstream source locks, chart sources, fail-closed value gates and umbrella dependencies.'
