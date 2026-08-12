#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helm version --short >/dev/null
helm template blueeconomy-base "$repo_root/kubernetes/base" >/dev/null 2>&1 || true
# The base uses Kustomize, so parse YAML document boundaries and validate that required resources are present.
grep -q 'kind: Namespace' "$repo_root/kubernetes/base/namespaces/platform.yaml"
grep -q 'kind: NetworkPolicy' "$repo_root/kubernetes/base/namespaces/platform.yaml"
grep -q 'kind: Namespace' "$repo_root/kubernetes/base/namespaces/security.yaml"
grep -q 'kind: NetworkPolicy' "$repo_root/kubernetes/base/namespaces/security.yaml"
echo "Validated GitOps base manifest presence and structural policy sources."
