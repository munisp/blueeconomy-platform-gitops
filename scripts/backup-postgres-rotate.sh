#!/usr/bin/env bash
set -Eeuo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/blueeconomy/postgres}"
DATABASE_URL="${DATABASE_URL:-}"
RETENTION_COUNT="${RETENTION_COUNT:-14}"
RETENTION_DAYS="${RETENTION_DAYS:-31}"
PREFIX="${BACKUP_PREFIX:-blueeconomy-postgres}"

fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "required command unavailable: $1"; }

[[ "$(id -u)" -eq 0 ]] || fail 'run as root or a dedicated backup account with write access'
[[ -n "$DATABASE_URL" ]] || fail 'DATABASE_URL is empty; refusing backup'
[[ "$RETENTION_COUNT" =~ ^[1-9][0-9]*$ ]] || fail 'RETENTION_COUNT must be a positive integer'
[[ "$RETENTION_DAYS" =~ ^[1-9][0-9]*$ ]] || fail 'RETENTION_DAYS must be a positive integer'
[[ "$PREFIX" =~ ^[A-Za-z0-9._-]+$ ]] || fail 'BACKUP_PREFIX contains unsafe characters'

require_command pg_dump
require_command pg_restore
require_command sha256sum
require_command find
require_command sort
require_command awk

install -d -o root -g root -m 0700 "$BACKUP_DIR"
# Do not echo DATABASE_URL or any command containing it.
now="$(date -u +%Y%m%dT%H%M%SZ)"
base="$BACKUP_DIR/${PREFIX}-${now}"
dump="${base}.dump"
checksum="${dump}.sha256"
metadata="${base}.meta"

umask 077
pg_dump --dbname="$DATABASE_URL" --format=custom --file="$dump" --no-owner --no-privileges
pg_restore --list "$dump" >/dev/null
sha256sum "$dump" > "$checksum"
printf 'created_at=%s\nformat=custom\nverified=pg_restore_list\n' "$now" > "$metadata"
chmod 0600 "$dump" "$checksum" "$metadata"

mapfile -t backups < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${PREFIX}-*.dump" -printf '%T@ %p\n' | sort -rn | awk '{print $2}')
if (( ${#backups[@]} > RETENTION_COUNT )); then
  for old in "${backups[@]:RETENTION_COUNT}"; do
    rm -f -- "$old" "${old%.dump}.dump.sha256" "${old%.dump}.meta"
  done
fi
find "$BACKUP_DIR" -maxdepth 1 -type f -name "${PREFIX}-*.dump" -mtime +"$RETENTION_DAYS" -delete
find "$BACKUP_DIR" -maxdepth 1 -type f -name "${PREFIX}-*.dump.sha256" -mtime +"$RETENTION_DAYS" -delete
find "$BACKUP_DIR" -maxdepth 1 -type f -name "${PREFIX}-*.meta" -mtime +"$RETENTION_DAYS" -delete

printf 'BACKUP_OK file=%s retention_count=%s retention_days=%s\n' "$dump" "$RETENTION_COUNT" "$RETENTION_DAYS"
