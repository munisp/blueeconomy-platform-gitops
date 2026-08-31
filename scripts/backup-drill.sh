#!/usr/bin/env bash
# Automated backup drill (WP-E): triggers a Velero backup from an approved
# schedule into the DRILL backup storage location (never the production
# restore path), waits for completion, and emits a pass/fail report with
# stable reason codes.
#
# Safety posture:
#   - The drill is NEVER destructive on the source: it only creates a
#     Backup CR. Restores are handled by scripts/restore-drill.sh and only
#     ever target a scratch namespace.
#   - Idempotent: re-running with the same --drill-id reuses the existing
#     drill backup name and re-evaluates its status instead of piling up
#     duplicates.
#   - Every external dependency is checked up front with a clear error.
#
# NOT_RUN: this script is reviewed and statically gated (bash -n,
# static analysis, --help/--preflight) but has never executed against a live
# cluster; first execution requires an approved staging environment and
# retained evidence (docs/dr-restore.md).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: backup-drill.sh --velero-namespace NS --schedule NAME \
         --drill-bsl NAME --evidence DIR [--drill-id ID] \
         [--timeout-seconds N] [--preflight] [--help]

Triggers a drill backup from the named Velero schedule into the drill
BackupStorageLocation (--drill-bsl, a non-production location), waits for
it to reach a terminal phase, and writes a pass/fail report to
<evidence>/backup-drill-<drill-id>.report.

Options:
  --velero-namespace NS   Namespace where the Velero server runs.
  --schedule NAME         Approved Velero Schedule to derive the backup from.
  --drill-bsl NAME        Drill BackupStorageLocation (must not be the
                          production default location).
  --evidence DIR          Directory for the drill report (created, mode 700).
  --drill-id ID           Stable drill identifier (default: UTC timestamp).
                          Reusing an ID makes the drill idempotent.
  --timeout-seconds N     Wait budget for backup completion (default 1800).
  --preflight             Check dependencies and inputs only; contact nothing.
  --help                  Show this help.

Reason codes (report RESULT line):
  DRILL_PASS                       backup completed and passed verification
  DRILL_PREFLIGHT_FAILED           missing dependency or invalid input
  DRILL_REFUSED_PRODUCTION_BSL     drill BSL is the production default
  DRILL_BACKUP_TRIGGER_FAILED      Backup CR could not be created
  DRILL_BACKUP_INCOMPLETE          terminal phase is not Completed
  DRILL_TIMEOUT                    backup did not finish within the budget
  DRILL_REPORT_UNVERIFIABLE        backup phase could not be read back

Exit status: 0 = DRILL_PASS, 1 = drill failed (see report), 2 = usage/preflight.
EOF
}

velero_ns=""; schedule=""; drill_bsl=""; evidence=""
drill_id="$(date -u +%Y%m%dT%H%M%SZ)"; timeout_s=1800; preflight=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --velero-namespace) velero_ns="${2:-}"; shift ;;
    --schedule) schedule="${2:-}"; shift ;;
    --drill-bsl) drill_bsl="${2:-}"; shift ;;
    --evidence) evidence="${2:-}"; shift ;;
    --drill-id) drill_id="${2:-}"; shift ;;
    --timeout-seconds) timeout_s="${2:-}"; shift ;;
    --preflight) preflight=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

fail_preflight() { echo "DRILL_PREFLIGHT_FAILED $*" >&2; exit 2; }

[ -n "$velero_ns" ] && [ -n "$schedule" ] && [ -n "$drill_bsl" ] && [ -n "$evidence" ] \
  || { usage >&2; exit 2; }
case "$drill_id" in *[!A-Za-z0-9._-]*|"") fail_preflight "drill-id must be DNS-safe: $drill_id" ;; esac
case "$timeout_s" in *[!0-9]*|"") fail_preflight "timeout-seconds must be an integer" ;; esac

# Up-front dependency check with clear errors.
command -v kubectl >/dev/null 2>&1 || fail_preflight "required dependency 'kubectl' not found on PATH"
command -v velero >/dev/null 2>&1 || fail_preflight "required dependency 'velero' (CLI) not found on PATH"

# Refuse to drill against the production default backup storage location.
if [ "$drill_bsl" = "default" ]; then
  echo "DRILL_REFUSED_PRODUCTION_BSL drill BSL must not be the production 'default' location" >&2
  exit 2
fi

mkdir -p "$evidence"; chmod 700 "$evidence"
report="$evidence/backup-drill-$drill_id.report"

if [ "$preflight" -eq 1 ]; then
  printf 'RESULT=%s\n' "DRILL_PREFLIGHT_OK no cluster, backup or storage system was contacted" > "$report"
  chmod 600 "$report"
  echo "Preflight passed; report: $report"
  exit 0
fi

backup_name="drill-$schedule-$drill_id"

# Idempotent trigger: reuse the existing drill backup when re-run.
if ! kubectl -n "$velero_ns" get backup.velero.io "$backup_name" >/dev/null 2>&1; then
  if ! velero --namespace "$velero_ns" backup create "$backup_name" \
      --from-schedule "$schedule" \
      --storage-location "$drill_bsl" >/dev/null 2>&1; then
    printf 'RESULT=%s backup=%s\n' "DRILL_BACKUP_TRIGGER_FAILED" "$backup_name" > "$report"
    chmod 600 "$report"
    echo "DRILL_BACKUP_TRIGGER_FAILED $backup_name" >&2
    exit 1
  fi
fi

# Wait for a terminal phase.
deadline=$(( $(date +%s) + timeout_s ))
phase=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  phase="$(kubectl -n "$velero_ns" get backup.velero.io "$backup_name" \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "$phase" in
    Completed|PartiallyFailed|Failed|FailedValidation) break ;;
  esac
  sleep 15
done

if [ -z "$phase" ]; then
  printf 'RESULT=%s backup=%s\n' "DRILL_REPORT_UNVERIFIABLE" "$backup_name" > "$report"
  chmod 600 "$report"
  echo "DRILL_REPORT_UNVERIFIABLE $backup_name" >&2
  exit 1
fi

{
  echo "drill_id=$drill_id"
  echo "backup=$backup_name"
  echo "phase=$phase"
  kubectl -n "$velero_ns" get backup.velero.io "$backup_name" \
    -o jsonpath='start={.status.startTimestamp} completion={.status.completionTimestamp} errors={.status.errors} warnings={.status.warnings}' 2>/dev/null || true
  echo
} > "$report"

if [ "$phase" = "Completed" ]; then
  echo "RESULT=DRILL_PASS backup=$backup_name phase=$phase" >> "$report"
  chmod 600 "$report"
  echo "DRILL_PASS $backup_name"
  exit 0
fi

result="DRILL_BACKUP_INCOMPLETE"
[ "$phase" = "InProgress" ] || [ "$phase" = "New" ] || [ "$phase" = "WaitingForPluginOperations" ] \
  && result="DRILL_TIMEOUT"
echo "RESULT=$result backup=$backup_name phase=$phase" >> "$report"
chmod 600 "$report"
echo "$result $backup_name phase=$phase" >&2
exit 1
