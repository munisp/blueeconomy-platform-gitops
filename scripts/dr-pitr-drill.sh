#!/usr/bin/env bash
set -Eeuo pipefail

# Logical-restore rehearsal. True PostgreSQL PITR requires a physical base backup
# and WAL archive; this script refuses to claim PITR without both.
fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"; }

BACKUP_FILE="${BACKUP_FILE:-}"
DR_DRILL_APPROVED="${DR_DRILL_APPROVED:-}"
DR_TARGET_NAME="${DR_TARGET_NAME:-blueeconomy-drill}"
DR_IMAGE="${DR_IMAGE:-postgres:16-alpine}"
DR_NETWORK="${DR_NETWORK:-blueeconomy-dr-drill-$$}"
DR_CONTAINER="${DR_CONTAINER:-blueeconomy-dr-target-$$}"
DR_DB="${DR_DB:-blueeconomy_restore}"
DR_USER="${DR_USER:-drill_user}"
DR_PASSWORD="${DR_PASSWORD:-}"
PITR_BASE_BACKUP="${PITR_BASE_BACKUP:-}"
PITR_WAL_ARCHIVE="${PITR_WAL_ARCHIVE:-}"
PITR_TARGET_TIME="${PITR_TARGET_TIME:-}"

[[ "$DR_DRILL_APPROVED" == yes ]] || fail 'set DR_DRILL_APPROVED=yes under approved change control'
[[ -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]] || fail 'BACKUP_FILE must point to a verified archive'
[[ "$BACKUP_FILE" != *production* && "$DR_TARGET_NAME" != *production* ]] || fail 'production targets are forbidden'
[[ -n "$DR_PASSWORD" && "$DR_PASSWORD" != *$'\n'* && "$DR_PASSWORD" != *$'\r'* ]] || fail 'DR_PASSWORD must be non-empty and single-line'
[[ -z "$PITR_TARGET_TIME" || ( -n "$PITR_BASE_BACKUP" && -n "$PITR_WAL_ARCHIVE" ) ]] || fail 'PITR_TARGET_TIME requires PITR_BASE_BACKUP and PITR_WAL_ARCHIVE'

require_cmd docker
require_cmd pg_restore
require_cmd sha256sum

if [[ -n "$PITR_TARGET_TIME" ]]; then
  [[ -d "$PITR_BASE_BACKUP" ]] || fail 'PITR_BASE_BACKUP must be a mounted physical base-backup directory'
  [[ -d "$PITR_WAL_ARCHIVE" ]] || fail 'PITR_WAL_ARCHIVE must be a mounted WAL archive directory'
  find "$PITR_WAL_ARCHIVE" -type f -print -quit | grep -q . || fail 'WAL archive is empty'
  printf 'PITR prerequisites present; target recovery time: %s\n' "$PITR_TARGET_TIME"
else
  printf '%s\n' 'Logical restore rehearsal mode: no PITR claim is made without a physical base backup and WAL archive.'
fi

checksum_file="${BACKUP_FILE}.sha256"
[[ -f "$checksum_file" ]] || fail "checksum file not found: $checksum_file"
( cd "$(dirname "$BACKUP_FILE")" && sha256sum -c "$(basename "$checksum_file")" )
pg_restore --list "$BACKUP_FILE" >/dev/null || fail 'archive listing validation failed'

DR_PASSWORD_FILE=""
cleanup() {
  set +e
  [[ -n "${DR_CONTAINER:-}" ]] && docker rm -f "$DR_CONTAINER" >/dev/null 2>&1
  [[ -n "${DR_NETWORK:-}" ]] && docker network rm "$DR_NETWORK" >/dev/null 2>&1
  [[ -n "${DR_PASSWORD_FILE:-}" ]] && rm -f "$DR_PASSWORD_FILE"
}
trap cleanup EXIT

DR_PASSWORD_FILE="$(mktemp)"
chmod 600 "$DR_PASSWORD_FILE"
printf 'POSTGRES_PASSWORD=%s\n' "$DR_PASSWORD" > "$DR_PASSWORD_FILE"
docker network create "$DR_NETWORK" >/dev/null
docker run -d --name "$DR_CONTAINER" --network "$DR_NETWORK" \
  -p 127.0.0.1::5432 --env-file "$DR_PASSWORD_FILE" \
  -e POSTGRES_DB="$DR_DB" -e POSTGRES_USER="$DR_USER" \
  "$DR_IMAGE" >/dev/null

until docker exec "$DR_CONTAINER" pg_isready -U "$DR_USER" -d "$DR_DB" >/dev/null 2>&1; do sleep 1; done
DR_PORT="$(docker port "$DR_CONTAINER" 5432/tcp | sed -n 's/.*:\([0-9][0-9]*\)$/\1/p')"
[[ "$DR_PORT" =~ ^[0-9]+$ ]] || fail 'could not determine isolated database port'

export PGPASSWORD="$DR_PASSWORD"
PGCONNECT_TIMEOUT=5 pg_restore --clean --if-exists --no-owner --exit-on-error \
  --dbname="postgresql://${DR_USER}@127.0.0.1:${DR_PORT}/${DR_DB}" "$BACKUP_FILE"

printf 'DR_REHEARSAL_PASS target=%s archive=%s\n' "$DR_TARGET_NAME" "$(basename "$BACKUP_FILE")"
