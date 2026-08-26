#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/deploy/external/docker-compose.yml"
ENV_FILE="${DEPLOY_ENV_FILE:-${ROOT_DIR}/deploy/external/.env}"
MIGRATION_FILE="${POSTGRES_MIGRATION_FILE:-${ROOT_DIR}/deploy/external/migrations/0000_blueeconomy_baseline.sql}"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

require_nonempty() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "required variable is empty: ${name}"
}

[[ -f "$COMPOSE_FILE" ]] || fail "Compose file not found: ${COMPOSE_FILE}"
[[ -f "$ENV_FILE" ]] || fail "operator environment file not found: ${ENV_FILE}"
[[ -f "$MIGRATION_FILE" ]] || fail "reviewed migration file not found: ${MIGRATION_FILE}"

require_command docker
require_command pg_dump
require_command pg_restore
require_command psql
require_command sha256sum

mode="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || true)"
[[ "$mode" == "600" || "$mode" == "400" ]] || fail "operator environment file must be mode 600 or 400"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

require_nonempty DATABASE_URL
require_nonempty KEYCLOAK_DB_NAME
require_nonempty KEYCLOAK_DB_USER
require_nonempty KEYCLOAK_DB_PASSWORD
require_nonempty KEYCLOAK_ADMIN_USERNAME
require_nonempty KEYCLOAK_ADMIN_PASSWORD
require_nonempty MINIO_ROOT_USER
require_nonempty MINIO_ROOT_PASSWORD
require_nonempty MINIO_SERVER_URL
require_nonempty MINIO_BROWSER_REDIRECT_URL
require_nonempty OIDC_ISSUER_URL
require_nonempty OIDC_CLIENT_ID
require_nonempty OIDC_CLIENT_SECRET
require_nonempty S3_ENDPOINT
require_nonempty S3_BUCKET
require_nonempty S3_ACCESS_KEY_ID
require_nonempty S3_SECRET_ACCESS_KEY

[[ "${POSTGRES_MIGRATION_APPROVED:-}" == "yes" ]] || fail "set POSTGRES_MIGRATION_APPROVED=yes only after approved change control"

printf '%s\n' 'Validating resolved Compose configuration...'
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config --quiet

printf '%s\n' 'Starting Keycloak database, Keycloak, OpenBao, and MinIO...'
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d keycloak-db keycloak openbao minio

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps

printf '%s\n' 'Running verified PostgreSQL backup and reviewed baseline migration...'
export POSTGRES_MIGRATION_FILE="$MIGRATION_FILE"
export POSTGRES_MIGRATION_APPROVED=yes
"${ROOT_DIR}/scripts/backup-and-migrate-postgres.sh"

printf '%s\n' 'Deployment command completed. OpenBao initialization/unseal and Keycloak realm/client setup remain operator-controlled steps.'
printf 'Compose file checksum: '
sha256sum "$COMPOSE_FILE" | cut -d' ' -f1
printf 'Migration file checksum: '
sha256sum "$MIGRATION_FILE" | cut -d' ' -f1
