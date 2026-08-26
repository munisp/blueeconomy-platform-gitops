#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${DEPLOY_ENV_FILE:-${ROOT_DIR}/deploy/external/.env}"
MIGRATION_FILE="${POSTGRES_MIGRATION_FILE:-${ROOT_DIR}/deploy/external/migrations/0000_blueeconomy_baseline.sql}"

fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
[[ -f "$ENV_FILE" ]] || fail "operator environment file not found"
mode="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || true)"
[[ "$mode" == "600" || "$mode" == "400" ]] || fail "operator environment file must be mode 600 or 400"
[[ -f "$MIGRATION_FILE" ]] || fail "reviewed migration file not found"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

[[ -n "${DATABASE_URL:-}" ]] || fail "DATABASE_URL is required"
[[ "${POSTGRES_MIGRATION_APPROVED:-no}" == "yes" ]] || fail "POSTGRES_MIGRATION_APPROVED=yes is required after approved change control"
command -v pg_dump >/dev/null 2>&1 || fail "pg_dump is required"
command -v pg_restore >/dev/null 2>&1 || fail "pg_restore is required"
command -v psql >/dev/null 2>&1 || fail "psql is required"

export BACKUP_DIR="${BACKUP_DIR:-${ROOT_DIR}/backups}"
export BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
export POSTGRES_MIGRATION_FILE="$MIGRATION_FILE"
"${ROOT_DIR}/scripts/backup-and-migrate-postgres.sh"
