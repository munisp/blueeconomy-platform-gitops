#!/usr/bin/env bash
set -euo pipefail
usage() { echo 'Usage: run-restore-reconciliation-drill.sh --preflight --values <approved-values.yaml> --evidence <directory>'; }
mode=""; values=""; evidence=""
while [ "$#" -gt 0 ]; do case "$1" in --preflight) mode=preflight;; --values) values="${2:-}"; shift;; --evidence) evidence="${2:-}"; shift;; *) usage >&2; exit 2;; esac; shift; done
[ "$mode" = preflight ] && [ -f "$values" ] && [ -n "$evidence" ] || { usage >&2; exit 2; }
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$evidence"; chmod 700 "$evidence"
helm lint "$repo_root/charts/regional-dr" --kube-version "${HELM_KUBE_VERSION:-1.28.0}" --values "$values" >/dev/null
rendered="$evidence/regional-dr-contract.yaml"
helm template regional-dr "$repo_root/charts/regional-dr" --namespace blueeconomy-recovery --kube-version "${HELM_KUBE_VERSION:-1.28.0}" --values "$values" > "$rendered"
chmod 600 "$rendered"
grep -Fq 'failover-mode: "manual-approved"' "$rendered"
grep -Fq 'blueeconomy.platform/control: regional-dr-contract' "$rendered"
printf '%s\n' "Preflight passed. No cluster, backup, routing, ledger, or partner system was contacted." > "$evidence/DRILL_PRECHECK.txt"
chmod 600 "$evidence/DRILL_PRECHECK.txt"
printf '%s\n' 'Recovery drill preflight passed; target restore execution remains gated on approved environment access.'
