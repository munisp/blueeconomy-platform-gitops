#!/usr/bin/env bash
set -Eeuo pipefail

: "${DATABASE_URL:?DATABASE_URL is required}"
backup_dir="${BACKUP_DIR:-./backups}"
retention_days="${BACKUP_RETENTION_DAYS:-14}"
[[ "$retention_days" =~ ^[0-9]+$ ]] || { echo 'BACKUP_RETENTION_DAYS must be a non-negative integer' >&2; exit 64; }
approval_marker="${POSTGRES_MIGRATION_APPROVED:?POSTGRES_MIGRATION_APPROVED must be set to yes}"
[[ "$approval_marker" == "yes" ]] || { echo 'POSTGRES_MIGRATION_APPROVED must equal yes' >&2; exit 64; }

command -v pg_dump >/dev/null || { echo 'pg_dump is required' >&2; exit 127; }
command -v pg_restore >/dev/null || { echo 'pg_restore is required' >&2; exit 127; }
command -v psql >/dev/null || { echo 'psql is required' >&2; exit 127; }

mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_file="$backup_dir/blueeconomy-${timestamp}.dump"

pg_dump --dbname="$DATABASE_URL" --format=custom --no-owner --no-acl --file="$backup_file"
chmod 600 "$backup_file"
pg_restore --list "$backup_file" >/dev/null
printf 'Backup verified: %s\n' "$backup_file"

migration_file="${POSTGRES_MIGRATION_FILE:-}"
if [[ -z "$migration_file" || ! -f "$migration_file" ]]; then
  echo 'POSTGRES_MIGRATION_FILE must point to the reviewed PostgreSQL migration SQL file' >&2
  exit 64
fi

psql --dbname="$DATABASE_URL" --set=ON_ERROR_STOP=1 --file="$migration_file"
printf 'Migration applied: %s\n' "$migration_file"

find "$backup_dir" -type f -name 'blueeconomy-*.dump' -mtime "+$retention_days" -delete
printf 'Retention cleanup complete: %s days\n' "$retention_days"
