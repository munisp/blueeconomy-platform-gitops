#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chart="$repo_root/charts/regional-dr"
version="${HELM_KUBE_VERSION:-1.28.0}"
failure="$(mktemp)"; values="$(mktemp)"
trap 'rm -f "$failure" "$values"' EXIT
if helm template regional-dr "$chart" --kube-version "$version" >/dev/null 2>"$failure"; then echo 'regional-dr rendered without approved values' >&2; exit 1; fi
# Helm values-schema validation can reject the unresolved recovery contract
# before template rendering. Both this schema denial and the template-level
# region assertion are valid fail-closed outcomes.
grep -Eq 'regionalDR\.primary\.region|values don.t meet the specifications of the schema' "$failure"
cat >"$values" <<'VALUES'
regionalDR:
  strategy: active-passive
  primary: {region: region-primary, clusterRef: cluster-primary}
  secondary: {region: region-secondary, clusterRef: cluster-secondary}
  rpoMinutes: 15
  rtoMinutes: 120
  backup: {artifactStoreRef: approved-immutable-archive, encryptionKeyRef: approved-recovery-key-ref, immutabilityDays: 30, restoreDrillMaxAgeHours: 2160}
  routing: {primaryEndpointRef: approved-primary-route, secondaryEndpointRef: approved-secondary-route, failoverRecordRef: approved-failover-record}
  failover: {mode: manual-approved, minimumApprovers: 2, approvalEvidenceRef: approved-two-person-evidence}
  drill: {changeId: CHG-RECOVERY-2026, evidenceLocationRef: approved-evidence-store}
VALUES
helm lint "$chart" --kube-version "$version" --values "$values" >/dev/null
rendered="$(helm template regional-dr "$chart" --namespace blueeconomy-recovery --kube-version "$version" --values "$values")"
grep -Fq 'blueeconomy.platform/control: regional-dr-contract' <<<"$rendered"
grep -Fq 'failover-mode: "manual-approved"' <<<"$rendered"
printf '%s\n' 'Validated regional DR fail-closed defaults and approved-value rendering.'
