# External identity and object storage deployment

This directory defines a cloud-agnostic self-hosted stack for deployments outside the managed development environment. Keycloak provides standards-based OIDC, its dedicated PostgreSQL database stores identity state, and MinIO provides S3-compatible object storage for evidence files.

Copy `secrets/external.env.example` to an operator-controlled `deploy/external/.env`, populate it through the deployment secret manager, and keep the file out of Git. The Compose stack binds to loopback by default; production exposure must be through an approved TLS reverse proxy or gateway with network policy and backups.

Start the services only after reviewing the images and the target change record:

```bash
set -a
. deploy/external/.env
set +a
docker compose --env-file deploy/external/.env -f deploy/external/docker-compose.yml config
docker compose --env-file deploy/external/.env -f deploy/external/docker-compose.yml up -d
```

The application database is separate from Keycloak’s database. Run `scripts/backup-and-migrate-postgres.sh` with `DATABASE_URL`, `POSTGRES_MIGRATION_FILE`, and `POSTGRES_MIGRATION_APPROVED=yes` only after a verified backup target and approved change window exist. The script refuses missing credentials, missing tooling, missing migration files, or any approval marker other than `yes`.

No production deployment, ingress, DNS, TLS private key, OIDC client secret, MinIO access key, or database credential is stored in this repository.
