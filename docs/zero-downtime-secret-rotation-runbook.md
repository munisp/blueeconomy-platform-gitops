# Blue Economy Zero-Downtime Secret Rotation Runbook

## Scope and safety boundary

This runbook rotates application, database, OIDC, object-storage, webhook, Grafana, and monitoring credentials without intentionally stopping the platform. It assumes at least two application instances behind the approved reverse proxy and a secret manager that supports versioned values. Never place populated secrets in Git, command arguments, CI logs, or chat. Use an approved change record, backup verification, and an operator rollback window before beginning.

A credential rotation is not zero-downtime if the target system supports only one active credential and cannot overlap old and new values. In that case, schedule a maintenance window or use a proxy/credential broker that supports overlap.

## Preconditions

| Check | Required result |
|---|---|
| Current service health | Monitor, health, recovery, Keycloak, MinIO, Prometheus, and Grafana are healthy |
| Backup | Fresh PostgreSQL custom-format backup exists and its checksum verifies |
| Secret manager | New versions can be created without deleting the current version |
| Deployment | At least two application instances are available for rolling restart |
| Rollback | Previous secret versions and configuration checksums are recorded |
| Observability | Alerts and logs are visible before rotation begins |

## Standard rotation sequence

1. Create a change record containing the secret names, owner, reason, start/end time, validation commands, and rollback owner. Record only secret identifiers and version IDs, never values.
2. Generate the replacement values in the approved secret manager. Use independent random values for database passwords, Keycloak admin/client secrets, MinIO access keys, Grafana admin credentials, webhook signing tokens, and GitHub credentials. Do not reuse one value across services.
3. Store the new version alongside the current version. Do not revoke the old version yet. Confirm the new value can be read by the intended service identity and that audit logging is enabled.
4. Update the external operator environment materialization to reference the new secret-manager versions. Write the file atomically, set owner `root:root`, and set mode `600`. Do not print the file.
5. Validate configuration syntax and run the deployment package’s preflight checks. Confirm Compose interpolation, systemd unit parsing, credential absence in tracked files, and service health checks.
6. Roll the application instances one at a time. Drain one instance from the reverse proxy, restart it with the new secret version, verify readiness and an authenticated health transaction, then return it to the pool before proceeding to the next instance.
7. Validate the data paths that use the rotated secret. For PostgreSQL, run a read-only probe and a transaction against the intended schema. For OIDC, complete a test authorization-code flow and verify issuer, audience, nonce, and session-cookie validation. For MinIO/S3, upload and retrieve a non-sensitive canary object, then delete it. For webhooks, send a signed test event to a controlled receiver. For Grafana, verify datasource health and alert delivery.
8. Observe logs, latency, error rates, authentication failures, storage errors, and alert delivery for at least one normal polling interval. Confirm no old-secret authentication errors are being retried indefinitely.
9. Revoke the old credential only after all instances use the new version and the validation window completes. If a dependency does not support overlap, revoke only after the rolling cutover has completed and the dependency probe passes.
10. Record the new version IDs, validation evidence, timestamps, and final service status in the change record. Never record secret values.

## Component-specific procedures

### PostgreSQL

Use a database-native overlap mechanism where supported. Create a new login role or password version, grant it the same least-privilege membership, test it from a drained application instance, roll the remaining instances, then revoke the old role/password after the connection pool has drained. Do not alter grants or drop the old role until active sessions using it are zero or the approved timeout has elapsed. Preserve the verified backup before changing roles.

### Keycloak/OIDC

Create a new confidential client secret or client version while the old secret remains valid. Deploy the new secret to one drained application instance and complete a full authorization-code callback. Roll the remaining instances, then rotate signing keys only through Keycloak’s supported key lifecycle so the old public key remains available during token overlap. Revoke the old client secret after token and session lifetimes have elapsed or after an approved session invalidation plan.

### MinIO/S3-compatible storage

Create a new access key with the same scoped policy, test a canary upload/download/delete, roll clients, and then disable the old access key. Keep root credentials out of application configuration. If the storage provider supports only one key, use a short controlled overlap through a credential broker or maintenance window.

### OpenBao and webhook/Grafana credentials

Create a new OpenBao token or policy-bound credential, update the external host’s secret-manager reference, reload or restart one consumer at a time, and verify audit events. For webhooks, rotate signing or endpoint credentials at the receiver and sender in an overlap order that preserves verification. For Grafana, create a new admin/service-account credential, validate datasource and contact-point delivery, then revoke the previous credential.

## Rollback

If any validation fails, stop the rollout, keep the old credential active, drain the affected instance, restore the previous secret-manager version, and restart only that instance. Revalidate the affected data path before returning it to service. If several instances fail, route traffic to the last known-good pool and restore the previous configuration version. Do not delete the new credential until the incident review is complete.

## Evidence to retain

Retain the change ID, secret version IDs, backup checksum, deployment artifact checksum, rolling restart timestamps, health-check output, database probe result, OIDC callback result, storage canary result, alert-delivery result, and rollback decision. Redact values, bearer tokens, cookies, signed URLs, and connection strings from all retained logs.
