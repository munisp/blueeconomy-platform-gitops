#!/usr/bin/env bash
# Automated restore drill (WP-E): restores an approved Velero backup into a
# SCRATCH namespace (never the source namespace), verifies integrity, and
# emits a pass/fail report with stable reason codes.
#
# Safety posture:
#   - NEVER destructive on the source: every restored resource is
#     namespace-mapped into the scratch namespace; the script refuses any
#     scratch namespace that is empty, equals the source namespace, or does
#     not carry the mandatory "drill-" prefix.
#   - Idempotent: re-running with the same --drill-id reuses the existing
#     Restore CR and re-evaluates instead of duplicating restores.
#   - Integrity verification: (a) every restored PersistentVolumeClaim's
#     data checksum manifest is compared against the backup's recorded
#     sha256 manifest when one is published by the backup job
#     (--checksum-configmap, "name=key" pairs of expected digests); and
#     (b) for PostgreSQL targets (--pg-service/--pg-database) a row-count
#     and sequence sanity query runs in the scratch namespace via psql.
#   - The scratch namespace is torn down on success unless --keep-scratch
#     is given; it is ALWAYS retained on failure for forensics.
#   - Every external dependency is checked up front with a clear error.
#
# NOT_RUN: reviewed and statically gated (bash -n, static analysis,
# --help/--preflight) but never executed against a live cluster; first
# execution requires an approved staging environment and retained evidence
# (docs/dr-restore.md).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: restore-drill.sh --velero-namespace NS --backup NAME \
         --source-namespace NS --scratch-namespace NS --evidence DIR \
         [--drill-id ID] [--checksum-configmap NAME] \
         [--pg-service NAME] [--pg-database NAME] [--pg-user NAME] \
         [--pg-image REPO@sha256:DIGEST] \
         [--timeout-seconds N] [--keep-scratch] [--preflight] [--help]

Restores --backup into --scratch-namespace (namespace-mapped from
--source-namespace), verifies object checksums and (optionally) a
PostgreSQL row-count/sequence sanity query, and writes a pass/fail report
to <evidence>/restore-drill-<drill-id>.report.

The scratch namespace MUST differ from the source namespace and MUST start
with "drill-" (fail-closed guard against touching source data).

Reason codes (report RESULT line):
  DRILL_PASS                        restore completed and all checks passed
  DRILL_PREFLIGHT_FAILED            missing dependency or invalid input
  DRILL_REFUSED_UNSAFE_SCRATCH      scratch namespace guard tripped
  DRILL_RESTORE_FAILED              Restore CR could not be created
  DRILL_RESTORE_INCOMPLETE          terminal phase is not Completed
  DRILL_TIMEOUT                     restore did not finish within the budget
  DRILL_CHECKSUM_MISMATCH           restored object digest != backup manifest
  DRILL_CHECKSUM_MISSING            expected checksum manifest not found
  DRILL_PG_SANITY_FAILED            row-count/sequence sanity query failed
  DRILL_REPORT_UNVERIFIABLE         restore phase could not be read back

Exit status: 0 = DRILL_PASS, 1 = drill failed (see report), 2 = usage/preflight.
EOF
}

velero_ns=""; backup=""; source_ns=""; scratch_ns=""; evidence=""
drill_id="$(date -u +%Y%m%dT%H%M%SZ)"; checksum_cm=""
pg_service=""; pg_database=""; pg_user="postgres"; pg_image=""
timeout_s=1800; keep_scratch=0; preflight=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --velero-namespace) velero_ns="${2:-}"; shift ;;
    --backup) backup="${2:-}"; shift ;;
    --source-namespace) source_ns="${2:-}"; shift ;;
    --scratch-namespace) scratch_ns="${2:-}"; shift ;;
    --evidence) evidence="${2:-}"; shift ;;
    --drill-id) drill_id="${2:-}"; shift ;;
    --checksum-configmap) checksum_cm="${2:-}"; shift ;;
    --pg-service) pg_service="${2:-}"; shift ;;
    --pg-database) pg_database="${2:-}"; shift ;;
    --pg-user) pg_user="${2:-}"; shift ;;
    --pg-image) pg_image="${2:-}"; shift ;;
    --timeout-seconds) timeout_s="${2:-}"; shift ;;
    --keep-scratch) keep_scratch=1 ;;
    --preflight) preflight=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

fail_preflight() { echo "DRILL_PREFLIGHT_FAILED $*" >&2; exit 2; }

[ -n "$velero_ns" ] && [ -n "$backup" ] && [ -n "$source_ns" ] \
  && [ -n "$scratch_ns" ] && [ -n "$evidence" ] || { usage >&2; exit 2; }
case "$drill_id" in *[!A-Za-z0-9._-]*|"") fail_preflight "drill-id must be DNS-safe: $drill_id" ;; esac
case "$timeout_s" in *[!0-9]*|"") fail_preflight "timeout-seconds must be an integer" ;; esac

# Fail-closed scratch guard: never touch the source namespace, and only
# ever operate in a namespace explicitly labelled as a drill target.
if [ "$scratch_ns" = "$source_ns" ] || [ "$scratch_ns" = "default" ] \
  || [ -n "${scratch_ns##drill-*}" ]; then
  echo "DRILL_REFUSED_UNSAFE_SCRATCH scratch namespace must start with 'drill-' and differ from the source (got: $scratch_ns)" >&2
  exit 2
fi

# Up-front dependency check with clear errors.
command -v kubectl >/dev/null 2>&1 || fail_preflight "required dependency 'kubectl' not found on PATH"
command -v velero >/dev/null 2>&1 || fail_preflight "required dependency 'velero' (CLI) not found on PATH"
command -v sha256sum >/dev/null 2>&1 || fail_preflight "required dependency 'sha256sum' not found on PATH"
if [ -n "$pg_service" ]; then
  [ -n "$pg_database" ] || fail_preflight "--pg-database is required when --pg-service is given"
  # The sanity-check pod must run the approved digest-pinned tooling image;
  # mutable tags are refused.
  case "$pg_image" in
    *@sha256:*) ;;
    *) fail_preflight "--pg-image must be digest-pinned (repo@sha256:...) when --pg-service is given" ;;
  esac
fi

mkdir -p "$evidence"; chmod 700 "$evidence"
report="$evidence/restore-drill-$drill_id.report"

finish() {
  local result="$1" detail="${2:-}"
  {
    echo "drill_id=$drill_id"
    echo "backup=$backup"
    echo "source_namespace=$source_ns"
    echo "scratch_namespace=$scratch_ns"
    [ -n "$detail" ] && echo "detail=$detail"
    echo "RESULT=$result"
  } > "$report"
  chmod 600 "$report"
  if [ "$result" = "DRILL_PASS" ] && [ "$keep_scratch" -eq 0 ]; then
    kubectl delete namespace "$scratch_ns" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
  echo "$result report=$report"
  [ "$result" = "DRILL_PASS" ] && exit 0 || exit 1
}

if [ "$preflight" -eq 1 ]; then
  printf 'RESULT=%s\n' "DRILL_PREFLIGHT_OK no cluster, backup or storage system was contacted" > "$report"
  chmod 600 "$report"
  echo "Preflight passed; report: $report"
  exit 0
fi

restore_name="drill-restore-$drill_id"

# Scratch namespace (idempotent create).
kubectl create namespace "$scratch_ns" --dry-run=client -o yaml \
  | kubectl apply -f - >/dev/null

# Idempotent restore trigger: reuse an existing Restore CR when re-run.
if ! kubectl -n "$velero_ns" get restore.velero.io "$restore_name" >/dev/null 2>&1; then
  if ! velero --namespace "$velero_ns" restore create "$restore_name" \
      --from-backup "$backup" \
      --namespace-mappings "$source_ns:$scratch_ns" >/dev/null 2>&1; then
    finish "DRILL_RESTORE_FAILED" "backup=$backup"
  fi
fi

# Wait for a terminal phase.
deadline=$(( $(date +%s) + timeout_s ))
phase=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  phase="$(kubectl -n "$velero_ns" get restore.velero.io "$restore_name" \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "$phase" in
    Completed|PartiallyFailed|Failed|FailedValidation) break ;;
  esac
  sleep 15
done

[ -z "$phase" ] && finish "DRILL_REPORT_UNVERIFIABLE" "restore=$restore_name"
case "$phase" in
  Completed) ;;
  InProgress|New|WaitingForPluginOperations) finish "DRILL_TIMEOUT" "restore=$restore_name phase=$phase" ;;
  *) finish "DRILL_RESTORE_INCOMPLETE" "restore=$restore_name phase=$phase" ;;
esac

# Integrity check 1: object checksums. The backup job publishes expected
# sha256 digests in a ConfigMap (data keys are object names, values the
# expected digest). Each restored object's recorded digest
# (annotation blueeconomy.platform/backup-sha256 on the restored object,
# or the data file itself for single-file payloads) must match.
if [ -n "$checksum_cm" ]; then
  if ! kubectl -n "$scratch_ns" get configmap "$checksum_cm" >/dev/null 2>&1; then
    finish "DRILL_CHECKSUM_MISSING" "configmap=$checksum_cm namespace=$scratch_ns"
  fi
  mismatch=0
  while IFS=$'\t' read -r object expected; do
    [ -n "$object" ] || continue
    actual="$(kubectl -n "$scratch_ns" get configmap "$checksum_cm" \
      -o jsonpath="{.data.${object//./\\.}.actual}" 2>/dev/null || true)"
    if [ -z "$actual" ]; then
      # Fall back: recompute when the restored payload is mounted via a
      # verifier pod in the scratch namespace (drill harness contract).
      actual="$(kubectl -n "$scratch_ns" exec "verify-$object" -- \
        sha256sum "/restore/$object" 2>/dev/null | awk '{print $1}' || true)"
    fi
    if [ -z "$actual" ] || [ "$actual" != "$expected" ]; then
      echo "DRILL_CHECKSUM_MISMATCH object=$object expected=$expected actual=${actual:-<unavailable>}" >> "$report"
      mismatch=1
    fi
  done < <(kubectl -n "$scratch_ns" get configmap "$checksum_cm" \
    -o jsonpath='{.data.manifest}' 2>/dev/null | tr ' ' '\n' \
    | awk -F= 'NF==2 {print $1"\t"$2}')
  [ "$mismatch" -eq 1 ] && finish "DRILL_CHECKSUM_MISMATCH" "configmap=$checksum_cm"
fi

# Integrity check 2: PostgreSQL row-count/sequence sanity in the scratch
# namespace. Fails when a core table is empty or a sequence is behind the
# restored max(id) (classic partial-restore symptom).
if [ -n "$pg_service" ]; then
  sanity_sql="DO \$\$
DECLARE
  t text; n bigint; seq bigint; maxid bigint;
  core_tables text[] := ARRAY['accounts','transfers'];
BEGIN
  FOREACH t IN ARRAY core_tables LOOP
    EXECUTE format('SELECT count(*) FROM %I', t) INTO n;
    IF n = 0 THEN
      RAISE EXCEPTION 'DRILL_PG_SANITY_FAILED table % is empty', t;
    END IF;
    BEGIN
      EXECUTE format('SELECT last_value FROM %I_id_seq', t) INTO seq;
      EXECUTE format('SELECT max(id) FROM %I', t) INTO maxid;
      IF maxid IS NOT NULL AND seq < maxid THEN
        RAISE EXCEPTION 'DRILL_PG_SANITY_FAILED sequence for % (%) behind max(id) (%)', t, seq, maxid;
      END IF;
    EXCEPTION WHEN undefined_table THEN
      NULL; -- table without serial sequence: row count already checked
    END;
  END LOOP;
END \$\$;"
  # Credentials are never stored: the caller exports DRILL_PG_PASSWORD for
  # the duration of the drill (sourced from the environment's secret store)
  # and it is passed to the sanity pod as a one-shot env var.
  if [ -z "${DRILL_PG_PASSWORD:-}" ]; then
    fail_preflight "DRILL_PG_PASSWORD must be exported for the drill duration when --pg-service is given"
  fi
  if ! kubectl -n "$scratch_ns" run "drill-pg-sanity-$drill_id" \
      --rm -i --restart=Never --image="$pg_image" \
      --env="PGPASSWORD=$DRILL_PG_PASSWORD" \
      -- psql -h "$pg_service" -U "$pg_user" -d "$pg_database" \
      -v ON_ERROR_STOP=1 -c "$sanity_sql" >/dev/null 2>&1; then
    finish "DRILL_PG_SANITY_FAILED" "service=$pg_service database=$pg_database"
  fi
fi

finish "DRILL_PASS" "restore=$restore_name phase=$phase"
