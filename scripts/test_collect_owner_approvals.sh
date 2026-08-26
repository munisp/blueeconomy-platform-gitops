#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
collector="$repo_root/scripts/collect_owner_approvals.py"
workspace="$(mktemp -d /tmp/blueeconomy-owner-approvals.XXXXXX)"
trap 'rm -rf "$workspace"' EXIT

docs="$workspace/docs"
records="$workspace/records"
evidence="$workspace/evidence"
mkdir -p "$docs" "$records"

printf '%s\n' 'Approved local OIDC record for test only.' > "$docs/oidc.md"
printf '%s\n' 'Approved local evidence retention record for test only.' > "$docs/evidence.md"
printf '%s\n' 'Approved local routing record for test only.' > "$docs/routing.md"

digest() { printf 'sha256:'; sha256sum "$1" | awk '{print $1}'; }
oidc_digest="$(digest "$docs/oidc.md")"
evidence_digest="$(digest "$docs/evidence.md")"
routing_digest="$(digest "$docs/routing.md")"

cat > "$workspace/policy.json" <<EOF
{
  "schemaVersion": "1.0",
  "changeId": "LOCAL-REVIEW-20260826-OWNER-001",
  "approvals": {
    "oidc": {"ownerRole": "IdentityOwner", "documentPath": "$docs/oidc.md"},
    "evidenceRetention": {"ownerRole": "ComplianceOwner", "documentPath": "$docs/evidence.md"},
    "routing": {"ownerRole": "RoutingOwner", "documentPath": "$docs/routing.md"}
  }
}
EOF

record() {
  local type="$1" role="$2" checksum="$3"
  cat > "$records/$type.json" <<EOF
{
  "schemaVersion": "1.0",
  "changeId": "LOCAL-REVIEW-20260826-OWNER-001",
  "recordType": "$type",
  "ownerRole": "$role",
  "decision": "APPROVED",
  "documentSha256": "$checksum",
  "signedAt": "2099-01-15T09:00:00Z",
  "signatureVerificationRef": "ticket:LOCAL-REVIEW-20260826-OWNER-001/$type",
  "signatureVerificationStatus": "VERIFIED"
}
EOF
}

record oidc IdentityOwner "$oidc_digest"
record evidenceRetention ComplianceOwner "$evidence_digest"
record routing RoutingOwner "$routing_digest"

python3 "$collector" --policy "$workspace/policy.json" --records "$records" --evidence "$evidence"
test "$(stat -c '%a' "$evidence")" = '700'
test "$(stat -c '%a' "$evidence/owner-approval-validation-summary.json")" = '600'
grep -Fq 'local-structure-only' "$evidence/owner-approval-validation-summary.json"

cat > "$workspace/mock-signature-verifier.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
grep -Fq '"signatureVerificationStatus": "VERIFIED"' "$1"
EOF
chmod 0755 "$workspace/mock-signature-verifier.sh"
python3 "$collector" --production --signature-verifier "$workspace/mock-signature-verifier.sh" --policy "$workspace/policy.json" --records "$records" --evidence "$workspace/production-evidence"
grep -Fq 'production-external-verifier' "$workspace/production-evidence/owner-approval-validation-summary.json"

sed -i 's/"decision": "APPROVED"/"decision": "REJECTED"/' "$records/routing.json"
set +e
python3 "$collector" --policy "$workspace/policy.json" --records "$records" --evidence "$workspace/reject-evidence" > "$workspace/reject.out" 2>&1
status=$?
set -e
test "$status" -eq 1
grep -Fq 'decision must be APPROVED' "$workspace/reject.out"

printf '%s\n' 'OWNER_APPROVAL_COLLECTOR_TEST_PASS'
