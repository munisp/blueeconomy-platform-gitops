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
[[ "$evidence" = /* ]] || { echo 'FAIL: evidence directory must be an absolute path.' >&2; exit 2; }
if [[ -n "${DR_RESTRICTED_EVIDENCE_ROOT:-}" && "$evidence" != "${DR_RESTRICTED_EVIDENCE_ROOT%/}"/* ]]; then
  echo 'FAIL: evidence directory is outside DR_RESTRICTED_EVIDENCE_ROOT.' >&2
  exit 2
fi
command -v helm >/dev/null || { echo 'FAIL: helm is required for fail-closed DR validation.' >&2; exit 2; }

values_mode=$(stat -c '%a' "$values")
values_mode_decimal=$((8#$values_mode))
(( (values_mode_decimal & 0077) == 0 )) || {
  echo 'FAIL: approved DR values must not be group/world accessible.' >&2
  exit 2
}

placeholder_pattern='fictional|do-not-use|DEMO-NOT-AUTHORIZED|SAMPLE-NONPROD|REQUIRED_FROM|To be assigned'
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

empty_required_key_pattern='^[[:space:]]*(strategy|region|clusterRef|rpoMinutes|rtoMinutes|artifactStoreRef|encryptionKeyRef|immutabilityDays|restoreDrillMaxAgeHours|primaryEndpointRef|secondaryEndpointRef|failoverRecordRef|minimumApprovers|approvalEvidenceRef|changeId|evidenceLocationRef):[[:space:]]*(""|\047\047|null|~|#.*)?[[:space:]]*$'
if grep -Ein "$empty_required_key_pattern" "$values"; then
  echo 'FAIL: required DR value is empty.' >&2
  exit 1
fi

grep -Eq '^[[:space:]]*strategy:[[:space:]]*active-passive[[:space:]]*$' "$values" || {
  echo 'FAIL: strategy must be active-passive.' >&2
  exit 1
}
grep -Eq '^[[:space:]]*mode:[[:space:]]*manual-approved[[:space:]]*$' "$values" || {
  echo 'FAIL: failover mode must be manual-approved.' >&2
  exit 1
}
if grep -Ein '(password|client[_-]?secret|bearer[[:space:]_-]|private[[:space:]_-]?key|access[[:space:]_-]?token)[[:space:]]*:' "$values"; then
  echo 'FAIL: approved DR values may contain references, not secret material.' >&2
  exit 1
fi

minimum_approvers=$(awk -F: '/^[[:space:]]*minimumApprovers:/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "$values")
[[ "$minimum_approvers" =~ ^[0-9]+$ && "$minimum_approvers" -ge 2 ]] || {
  echo 'FAIL: minimumApprovers must be an integer of at least 2.' >&2
  exit 1
}

for numeric_key in rpoMinutes rtoMinutes immutabilityDays restoreDrillMaxAgeHours; do
  numeric_value=$(awk -F: -v key="$numeric_key" '$1 ~ "^[[:space:]]*" key "[[:space:]]*$" {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$values")
  [[ "$numeric_value" =~ ^[0-9]+$ && "$numeric_value" -gt 0 ]] || {
    echo "FAIL: $numeric_key must be a positive integer." >&2
    exit 1
  }
done

mkdir -p "$evidence"
[[ ! -L "$evidence" ]] || { echo 'FAIL: evidence directory must not be a symlink.' >&2; exit 2; }
chmod 700 "$evidence"
[[ "$(stat -c '%a' "$evidence")" == '700' ]] || { echo 'FAIL: evidence directory permissions must be 700.' >&2; exit 2; }
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helm lint "$repo_root/charts/regional-dr" --kube-version "${HELM_KUBE_VERSION:-1.28.0}" --values "$values" >/dev/null
helm template regional-dr "$repo_root/charts/regional-dr" --namespace blueeconomy-recovery --kube-version "${HELM_KUBE_VERSION:-1.28.0}" --values "$values" > "$evidence/approved-regional-dr-contract.yaml"
chmod 600 "$evidence/approved-regional-dr-contract.yaml"
grep -Fq 'failover-mode: "manual-approved"' "$evidence/approved-regional-dr-contract.yaml"
grep -Fq 'blueeconomy.platform/control: regional-dr-contract' "$evidence/approved-regional-dr-contract.yaml"

printf '%s\n' 'APPROVED_DR_SUBMISSION_VERIFIER_PASS' | tee "$evidence/APPROVED_DR_SUBMISSION_VERIFIER.txt"
chmod 600 "$evidence/APPROVED_DR_SUBMISSION_VERIFIER.txt"
