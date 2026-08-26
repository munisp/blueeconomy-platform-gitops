# External Keycloak and MinIO Deployment Runbook

**Scope:** Self-hosted external deployment of Blue Economy identity and evidence storage.
**Repository package:** `deploy/external/` on branch `remediation/gitops-policy-required-gate-20260826`.
**Safety rule:** Do not use fictional values, development preview URLs, or production credentials from chat or source control.

## 1. Prepare the target host

Use an approved Linux host or Kubernetes-capable runner with Docker Engine, Docker Compose v2, `pg_dump`, `pg_restore`, and `psql` installed. Restrict administrative access, apply operating-system updates, configure a firewall, and place the services behind an approved TLS reverse proxy or gateway. Do not expose the default Keycloak or MinIO ports directly to the public internet.

Clone the reviewed GitOps branch and verify the commit before running anything:

```bash
git clone https://github.com/munisp/blueeconomy-platform-gitops.git
cd blueeconomy-platform-gitops
git checkout remediation/gitops-policy-required-gate-20260826
git rev-parse HEAD
```

The expected deployment package commits are `e501c6e` and `e9c0fbb` or descendants containing both.

## 2. Populate secrets out of band

Copy the committed template into an operator-only file. Populate it through the approved secret manager or a protected terminal. Set file permissions to owner-only and never commit the file:

```bash
cp secrets/external.env.example deploy/external/.env
chmod 600 deploy/external/.env
$EDITOR deploy/external/.env
```

Required values include separate Keycloak database credentials, a strong Keycloak bootstrap administrator password, MinIO root credentials, the approved MinIO server and console URLs, the application PostgreSQL URL, and application OIDC/S3 values. Use unique randomly generated values and do not reuse the Keycloak administrator password as a service credential.

## 3. Validate the resolved configuration

Run the configuration check before starting services. It must fail if required variables are empty:

```bash
set -a
. deploy/external/.env
set +a
docker compose --env-file deploy/external/.env \
  -f deploy/external/docker-compose.yml config --quiet
bash scripts/backup-and-migrate-postgres.sh
```

The last command is intentionally expected to refuse until `DATABASE_URL`, `POSTGRES_MIGRATION_FILE`, and `POSTGRES_MIGRATION_APPROVED=yes` are set. Do not bypass that refusal.

## 4. Start PostgreSQL and Keycloak

Start the identity database and Keycloak. The Compose network keeps the database internal and binds Keycloak to loopback by default:

```bash
docker compose --env-file deploy/external/.env \
  -f deploy/external/docker-compose.yml up -d keycloak-db keycloak

docker compose --env-file deploy/external/.env \
  -f deploy/external/docker-compose.yml ps
curl --fail --silent --show-error \
  http://127.0.0.1:${KEYCLOAK_PORT:-8080}/health/ready
```

Log into the Keycloak administration console through the approved TLS endpoint. Create the Blue Economy realm, register the application client, configure exact redirect URIs for the external application, enable the approved identity providers, and create only the roles required by the platform claim matrix. Disable insecure direct access and require MFA for administrative accounts according to the approved security policy.

Record the realm issuer URL and client ID in the external secret manager. Do not place the client secret, administrator password, or signing keys in Git.

## 5. Start and configure MinIO

Start MinIO after confirming the storage volume is on encrypted durable storage:

```bash
docker compose --env-file deploy/external/.env \
  -f deploy/external/docker-compose.yml up -d minio

docker compose --env-file deploy/external/.env \
  -f deploy/external/docker-compose.yml ps
curl --fail --silent --show-error \
  http://127.0.0.1:${MINIO_API_PORT:-9000}/minio/health/live
```

Through the protected MinIO console, create the evidence bucket named by `S3_BUCKET`, enable versioning if required by the retention policy, configure server-side encryption using the approved key-management arrangement, and create a least-privilege application access key. The application key must not be the MinIO root key. Configure lifecycle retention and object-lock settings only after compliance approval because they affect deletion and recovery behavior.

Set the mobile service’s `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, and `S3_SECRET_ACCESS_KEY` in the target secret manager. Use the internal service address for server-to-server access and the approved TLS endpoint for any browser-mediated operation.

## 6. Back up and apply the application PostgreSQL baseline

The application database is distinct from Keycloak’s database. Take a verified custom-format backup before applying the reviewed baseline:

```bash
export DATABASE_URL='postgresql://...'
export BACKUP_DIR='/var/backups/blueeconomy'
export POSTGRES_MIGRATION_FILE="$PWD/deploy/external/migrations/0000_blueeconomy_baseline.sql"
export POSTGRES_MIGRATION_APPROVED=yes
bash scripts/backup-and-migrate-postgres.sh
```

The script runs `pg_dump`, validates the dump with `pg_restore --list`, applies the SQL with `ON_ERROR_STOP`, and removes backups older than `BACKUP_RETENTION_DAYS`. Retain the dump checksum, migration checksum, operator identity, change ID, timestamps, and database health output in the change record. If the target database already contains data or a schema with the same tables, stop and perform a reviewed compatibility migration rather than applying the clean baseline.

## 7. Configure and validate the application

Configure the externalized mobile service with the Keycloak issuer/client values, application PostgreSQL URL, and MinIO S3 values. Start the service through its approved deployment mechanism and verify:

```bash
curl --fail --silent --show-error https://APPROVED_APP_HOST/api/health
```

Perform an authorized OIDC login, verify the signed session and role claims, upload a non-sensitive evidence test object, verify access control, and confirm that unauthorized reads and writes are denied. Run the API-edge negative tests and retain their signed evidence. Do not use a local fictional fixture as production evidence.

## 8. Rollback and incident boundaries

If Keycloak fails health checks, stop exposure at the reverse proxy and preserve logs. If MinIO fails, disable evidence upload while retaining local fail-closed behavior. If the PostgreSQL migration fails, stop immediately, retain the failed command output, and restore only through the approved database recovery procedure. Never delete volumes or run destructive SQL as an ad hoc rollback.

The committed Compose file is a reproducible deployment definition, not proof that an instance is provisioned. Target-side health, TLS, backup, OIDC, storage, API-edge, and DR evidence must be attached to the approved change record before production release.
