#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER="blueeconomy-postgres-test-$$"
WORK_DIR="$(mktemp -d)"
ENV_FILE="$WORK_DIR/test.env"
MIGRATION_FILE="$WORK_DIR/test-migration.sql"
BACKUP_DIR="$WORK_DIR/backups"

cleanup() {
  docker rm --force "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || fail 'Docker is required on the external runner'
command -v psql >/dev/null 2>&1 || fail 'psql is required on the external runner'
command -v pg_isready >/dev/null 2>&1 || fail 'pg_isready is required on the external runner'
[[ -x "$ROOT_DIR/scripts/backup-and-migrate-postgres.sh" ]] || fail 'backup script must be executable'

password="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
cat > "$ENV_FILE" <<EOF
POSTGRES_PASSWORD=$password
EOF
chmod 600 "$ENV_FILE"

# This is a disposable test credential, never a production secret.
docker run --detach --name "$CONTAINER" --publish 127.0.0.1::5432 \
  --env POSTGRES_DB=blueeconomy_test \
  --env POSTGRES_USER=blueeconomy_test \
  --env-file "$ENV_FILE" \
  postgres:16-alpine >/dev/null

port="$(docker port "$CONTAINER" 5432/tcp | sed -n 's/.*:\([0-9][0-9]*\)$/\1/p')"
[[ "$port" =~ ^[0-9]+$ ]] || fail 'could not determine the random PostgreSQL port'

database_url="postgresql://blueeconomy_test:${password}@127.0.0.1:${port}/blueeconomy_test"
for attempt in $(seq 1 60); do
  if PGPASSWORD="$password" pg_isready --dbname="$database_url" >/dev/null 2>&1; then break; fi
  [[ "$attempt" -lt 60 ]] || fail 'disposable PostgreSQL did not become ready'
  sleep 1
done

cat > "$MIGRATION_FILE" <<'SQL'
CREATE TABLE IF NOT EXISTS migration_probe (
  id integer PRIMARY KEY,
  marker text NOT NULL
);
INSERT INTO migration_probe (id, marker) VALUES (1, 'external-runner-test')
ON CONFLICT (id) DO UPDATE SET marker = EXCLUDED.marker;
SQL
chmod 600 "$MIGRATION_FILE"
mkdir -m 700 "$BACKUP_DIR"

DATABASE_URL="$database_url" \
POSTGRES_MIGRATION_APPROVED=yes \
POSTGRES_MIGRATION_FILE="$MIGRATION_FILE" \
BACKUP_DIR="$BACKUP_DIR" \
BACKUP_RETENTION_DAYS=1 \
  "$ROOT_DIR/scripts/backup-and-migrate-postgres.sh"

PGPASSWORD="$password" psql --dbname="$database_url" --command \
  "SELECT 1 FROM migration_probe WHERE id = 1 AND marker = 'external-runner-test';" \
  | grep -q '^ *1$' || fail 'migration probe verification failed'

backup_count="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'blueeconomy-*.dump' | wc -l)"
[[ "$backup_count" -eq 1 ]] || fail "expected exactly one verified backup, found $backup_count"
printf '%s\n' 'Disposable PostgreSQL backup and migration test passed; container and temporary credentials will be removed.'
