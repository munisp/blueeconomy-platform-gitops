# Production Deployment Guardrails

## 1. Protected change categories

| Category | Examples | Required approval and evidence |
|---|---|---|
| TigerBeetle formation | Cluster ID, replica count, address order, data-file format, storage class, PVC deletion or restoration. | Finance owner, SRE, security and independent reconciliation owner; tested migration/recovery plan. |
| Payment-operating model | Mojaloop participant routing, settlement provider, administrator, limits, payment certificate, fraud/AML integration. | Financial operations, legal/regulatory owner, compliance, security and participant owner. |
| Data access | Sedona object-store/catalog/Kafka access, table classification, source/target product, CRS/geometry transformations. | Data owner/steward, privacy/security and platform data engineering. |
| Platform boundary | Public/partner API route, Keycloak client, network policy exception, secret/KMS reference, node pool. | API/identity/security/SRE owner and threat-model evidence. |
| Image or chart change | TigerBeetle/Mojaloop/Sedona/Spark/Operator release, base image or dependency change. | SBOM, vulnerability scan, compatibility test, rollback/restore evidence and staged release record. |

## 2. Prohibited actions

The following are prohibited in production unless an emergency change is approved and retrospectively reviewed:

1. Applying Helm charts with `--set` to provide credentials, passwords, certificates or private keys.
2. Using a mutable `latest` tag, an unverified image, an unpinned chart version, or an unreviewed upstream repository.
3. Exposing TigerBeetle, Mojaloop administration, databases, Redis, Kafka or Spark UI directly to the public internet.
4. Changing TigerBeetle formation values in place; deleting its PVCs to correct a deployment; scaling it down because of a normal maintenance event; or reformatting a non-empty data volume.
5. Bypassing GitOps, peer review, policy checks, security scanning, approval gates or audit logging.
6. Scheduling Sedona jobs with unrestricted Kubernetes API, Secret, database or object-store permissions.
7. Declaring a payment or financial reconciliation complete based solely on application availability or a Helm release status.

## 3. Mandatory release evidence

Before a production promotion, retain the pull request, signed/approved values change, rendered manifest, chart/image digest, SBOM, vulnerability scan, policy result, integration-test result, backup/restore or equivalent recovery test, SLO/monitoring dashboard, change ticket, rollback plan and service-owner approval. For financial services, add the current reconciliation report and finance operations acceptance.

## 4. Emergency change

Emergency access is time-limited, individually attributable, MFA-protected and logged. The incident commander must document reason, scope, affected data/service, actions, rollback/recovery result and post-incident review. Emergency access cannot waive regulatory/financial evidence or cause irreversible changes to TigerBeetle cluster formation or production financial records.
