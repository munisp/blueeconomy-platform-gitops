#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo 'Usage: verify-approved-dr-submission.sh --values <approved-values.yaml> --ticket <approved-ticket.md> --evidence <restricted-directory>' >&2
}

values=""
ticket=""
evidence=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --values) values="${2:-}"; shift ;;
    --ticket) ticket="${2:-}"; shift ;;
    --evidence) evidence="${2:-}"; shift ;;
    *) usage; exit 2 ;;
  esac
  shift
done

[[ -f "$values" && -f "$ticket" && -n "$evidence" ]] || { usage; exit 2; }
command -v helm >/dev/null || { echo 'FAIL: helm is required for fail-closed DR validation.' >&2; exit 2; }

placeholder_pattern='fictional|do-not-use|DEMO-NOT-AUTHORIZED|SAMPLE-NONPROD|REQUIRED_FROM|To be assigned|^[[:space:]]*$'
if grep -Ein "$placeholder_pattern" "$values" "$ticket"; then
  echo 'FAIL: fictional or unresolved placeholder value found.' >&2
  exit 1
fi

for key in \
  'strategy:' 'region:' 'clusterRef:' 'rpoMinutes:' 'rtoMinutes:' \
  'artifactStoreRef:' 'encryptionKeyRef:' 'immutabilityDays:' \
  'restoreDrillMaxAgeHours:' 'primaryEndpointRef:' 'secondaryEndpointRef:' \
  'failoverRecordRef:' 'mode: manual-approved' 'minimumApprovers:' \
  'approvalEvidenceRef:' 'changeId:' 'evidenceLocationRef:'; do
  grep -Fq "$key" "$values" || { echo "FAIL: missing required values key: $key" >&2; exit 1; }
done

minimum_approvers=$(awk -F: '/^[[:space:]]*minimumApprovers:/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "$values")
[[ "$minimum_approvers" =~ ^[0-9]+$ && "$minimum_approvers" -ge 2 ]] || {
  echo 'FAIL: minimumApprovers must be an integer of at least 2.' >&2
  exit 1
}

mkdir -p "$evidence"
chmod 700 "$evidence"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helm lint "$repo_root/charts/regional-dr" --kube-version "${HELM_KUBE_VERSION:-1.28.0}" --values "$values" >/dev/null
helm template regional-dr "$repo_root/charts/regional-dr" --namespace blueeconomy-recovery --kube-version "${HELM_KUBE_VERSION:-1.28.0}" --values "$values" > "$evidence/approved-regional-dr-contract.yaml"
chmod 600 "$evidence/approved-regional-dr-contract.yaml"
grep -Fq 'failover-mode: "manual-approved"' "$evidence/approved-regional-dr-contract.yaml"
grep -Fq 'blueeconomy.platform/control: regional-dr-contract' "$evidence/approved-regional-dr-contract.yaml"

printf '%s\n' 'APPROVED_DR_SUBMISSION_VERIFIER_PASS' | tee "$evidence/APPROVED_DR_SUBMISSION_VERIFIER.txt"
chmod 600 "$evidence/APPROVED_DR_SUBMISSION_VERIFIER.txt"
