# Blue Economy Platform: Core Services Deployment Guide

**Audience:** Ministry platform engineering, financial-operations, security, SRE, data-engineering and supplier teams.  
**Scope:** Production deployment patterns for **TigerBeetle**, **Mojaloop** and **Apache Sedona** on Kubernetes.  
**Status:** Implementation baseline. The selected product releases, storage class, cloud/on-premises topology, network addresses, secret manager and regulated financial integration must be approved before production change.

## 1. Deployment Position and Non-Negotiable Boundaries

The three services have different risk and operational models. **TigerBeetle** is the platform’s high-integrity, double-entry **sub-ledger**; it does not replace the legally authoritative record maintained by an authorized fund administrator, bank or treasury. **Mojaloop** is a payment interoperability/switching component deployed only after participant, settlement, compliance and operating-accountability models are approved. **Apache Sedona** is a spatial compute library/runtime, normally deployed in version-pinned Spark applications; it is not a standing, shared transactional service.

> **Production gate:** No Helm release is sufficient evidence of financial, safety, regulatory or operational readiness. The service owner must sign the applicable legal, data-sharing, security, disaster-recovery, workload, support and reconciliation acceptance artefacts before a production release.

| Service | Kubernetes deployment unit | State of record | Primary owner | Hard production boundary |
|---|---|---|---|---|
| TigerBeetle | Dedicated `StatefulSet` with fixed ordered replicas and one persistent volume per replica. | TigerBeetle sub-ledger; legal account remains with authorized provider. | Finance Platform/SRE jointly. | Never change `clusterID`, replica count or address order after initialization; no live data without reconciliation and recovery acceptance. |
| Mojaloop | Pinned upstream Helm deployment plus Ministry overlay/values; backing services isolated. | Mojaloop switch/application state and authorised external provider records. | Payments Platform/Financial Operations. | Never expose internal admin interfaces or deploy before participant, settlement, fraud/AML and incident roles are agreed. |
| Apache Sedona | Spark applications/jobs submitted through a hardened Spark Operator, with Sedona image/package pinned. | Governed Delta/Parquet data products, not Spark pod disks. | Geospatial Data Platform. | No unrestricted data access, no long-lived shared notebook pods, and no decision automation outside approved human workflows. |

TigerBeetle’s official guidance requires every replica to be formatted with a globally unique cluster ID, a replica count and a unique replica index; the entire cluster and clients use the same ordered address list. It also states that current cluster size cannot be changed after creation and describes six dedicated replicas as its production pattern.[1] Kubernetes StatefulSets provide stable network identity, stable storage and ordered Pod semantics for stateful applications, making them the appropriate workload primitive for this implementation.[2]

Mojaloop’s official deployment documentation follows a Helm-based installation model, with separate backend dependencies, configurable values, ingress verification and test tooling.[3] Apache Sedona supports distributed batch processing through SedonaSpark and real-time spatial analytics through SedonaFlink; this guide uses Spark-on-Kubernetes first, and adopts SedonaFlink only after a dedicated real-time spatial need is accepted.[4]

## 2. Prerequisites and Landing Zone

### 2.1 Environments and namespace isolation

Deploy to separate production and non-production clusters whenever possible. If an exception is approved, use separate namespaces, node pools, network segmentation, KMS keys, identities and GitOps projects. Namespaces are not merely organizational labels; they are a release, policy, cost and access boundary.

| Namespace | Purpose | Workload types | Access / network rule |
|---|---|---|---|
| `blueeco-system` | Cluster-level controllers shared by the platform. | External Secrets, policy controller, monitoring agents, Spark Operator. | Platform SRE only; no business data workload. |
| `blueeco-tigerbeetle-prod` | TigerBeetle financial sub-ledger. | StatefulSet, headless service, PDB, metrics sidecar if approved. | Private only; only finance API namespace and controlled admin bastion may connect. |
| `blueeco-mojaloop-prod` | Mojaloop switch and approved backing services. | Upstream Mojaloop release, scoped dependencies and adapters. | APISIX is the north-south ingress; service-to-service paths are allow-listed. |
| `blueeco-geo-prod` | Spark Operator and Sedona SparkApplication execution. | Spark drivers/executors, scheduled jobs, configuration. | Private data-plane access only to approved Kafka/object store/catalog endpoints. |
| `blueeco-observability` | Metrics, logs and audit integration. | Collectors, alerting and dashboards. | Receives minimized telemetry; no unrestricted business-data queries. |

### 2.2 Required platform capabilities

Before service installation, the platform team must provide the following capabilities and demonstrate them in non-production:

| Capability | Minimum acceptance evidence |
|---|---|
| Kubernetes cluster | Supported Kubernetes version, separate system/stateful/data node pools, multi-zone topology where available, audited administrative access and CIS-style hardening evidence. |
| Storage | A tested storage class with per-volume encryption, snapshots, volume expansion policy, retention/restore procedures and performance benchmark. TigerBeetle uses dedicated low-latency persistent volumes. |
| Network | Private cluster endpoints or equivalent controls, default-deny NetworkPolicies, egress gateway/proxy, internal DNS, firewall rules, mTLS strategy and time synchronization. |
| Identity | Keycloak/approved federation, workload identity, MFA, short-lived credentials, separate GitOps deploy identity and emergency-access review. |
| Secrets and keys | External secret manager/KMS/HSM. Helm values hold references only; no plaintext secret or private key is committed. |
| Supply chain | Private registry, image signing/verification, SBOM, vulnerability scanning, digest pinning, base-image policy and approved release promotion. |
| GitOps | A reconciler such as Argo CD or Flux, environment-specific repository controls, protected production promotion and immutable deployment history. |
| Observability | OpenTelemetry, metrics/logs/alerts, Wazuh/OpenSearch integration, dashboard ownership, SLOs and alert runbooks. |
| Backup and recovery | Written RPO/RTO, restore drill, data-corruption scenario, off-cluster backup copy, documented manual fallback and sign-off by service owner. |

### 2.3 Baseline engineering controls

Each workload must set resource requests/limits, non-root runtime where supported, read-only root filesystem where compatible, dropped Linux capabilities, seccomp profile, liveness/readiness/startup probes, topology-spread/anti-affinity, PodDisruptionBudget, NetworkPolicy, dedicated ServiceAccount, structured logs, metrics and trace correlation. Every chart must pass `helm lint`, template rendering, policy validation, vulnerability/SBOM checks and a namespace-restricted installation test in CI before promotion.

## 3. Repository, Release and Secrets Model

The deliverable repository uses a thin Ministry-owned overlay rather than silently forking upstream projects. The `tigerbeetle` chart is bespoke because TigerBeetle has cluster formation invariants. The `mojaloop-overlay` chart is a governance/configuration envelope for a **pinned upstream Mojaloop chart release**. The `sedona-spark-jobs` chart is a template library and scheduled-job deployment path that assumes an operator-managed Spark runtime.

```text
blueeconomy-platform-gitops/
├── charts/
│   ├── core-services/                # Disabled-by-default umbrella; no secrets
│   ├── tigerbeetle/                  # Dedicated StatefulSet pattern with render gates
│   ├── mojaloop-overlay/             # Release-control envelope for a pinned upstream release
│   └── sedona-spark-jobs/            # SparkApplication and spatial job templates
├── docs/
│   └── core-services-deployment-guide.md
├── kubernetes/                       # Platform namespace and base policy sources
├── policies/
│   └── core-services-production-guardrails.md
└── scripts/
    └── validate-manifests.sh
```

No environment values file is committed in this baseline because the Ministry has not supplied an approved environment registry. Each source chart contains render-time guards that reject missing image digests, infrastructure identifiers and authority values. Environment-specific values belong in the controlled environment repository after approval; secret material never belongs in either repository.

### 3.1 Immutable and protected values

| Value class | Examples | Change process |
|---|---|---|
| Immutable after initialization | TigerBeetle cluster ID, replica count, ordinal/address order, ledger account model. | New cluster/migration plan, data/reconciliation approval and independent test. Do not `helm upgrade` these in place. |
| Protected production values | Image digest, storage class/size, node selector, service account, network CIDR, encryption/key reference, Mojaloop release version. | Peer-reviewed pull request, security/SRE approval, staged promotion and rollback plan. |
| Environment values | Namespace, DNS suffix, resource sizing, replica count where supported, schedule, bucket/catalog endpoints. | GitOps promotion through dev → staging → production. |
| Secret references | KMS key alias, secret-store path, certificate reference, third-party credential reference. | Separate secret-management change with audit; never place the secret content in a values file. |

## 4. TigerBeetle Deployment Procedure

### 4.1 Topology

Production uses a **six-replica** StatefulSet spanning distinct nodes and, where available, availability/failure zones. Each Pod receives an immutable ordinal (`0`–`5`), its own persistent volume and a stable DNS name through a headless Service. A private ClusterIP service presents the full ordered peer list only to authorized finance services. The service is never exposed by public ingress.

| Design element | Required configuration | Reason |
|---|---|---|
| StatefulSet | `replicas: 6`, `podManagementPolicy: OrderedReady`, partitioned/controlled upgrade plan. | Keeps ordinal identity and avoids unsafe generic scale operations. |
| Headless service | `clusterIP: None`; selector matches stateful pods. | Creates stable peer DNS identities. |
| Persistent storage | One encrypted PVC per replica; `ReadWriteOncePod` where supported; no shared volume. | Preserves replica data and prevents concurrent access. |
| Node/zone placement | Required anti-affinity and topology spread; dedicated node pool. | Reduces correlated node/zone failures. |
| Network | Default deny; only fixed peer UDP/TCP ports and approved clients; no internet egress. | Protects financial ledger traffic and prevents ungoverned access. |
| Initialization | A controlled one-time formatting job/installer step creates each data file. | Cluster ID, replica count and ordinal must be correct before first start. |
| Monitoring | Process health, client request/error/latency, disk capacity/latency, replica reachability, backup/restore result. | Ensures operational faults are noticed before financial impact. |

### 4.2 Preflight and initialization

1. Generate a cryptographically random 128-bit cluster ID through the approved key/secret process. Record its non-secret identifier in the change record. Never use the test cluster ID `0`.
2. Confirm the desired replica count is six and the ordered host list is final. The production chart does not support a mutable replica count.
3. Provision six encrypted persistent volumes using the approved storage class. Verify each volume meets latency and durability expectations with a non-production benchmark.
4. Apply namespace, service account, network policy, headless service and PDB. Confirm every ordinal resolves its peer DNS name from a test Pod.
5. Run the controlled initial format step once per ordinal. The step writes the data file with the cluster ID, replica count and unique replica index. It must not reformat a non-empty volume.
6. Start the StatefulSet under the ordered address list. Confirm the cluster primary/replica state using the selected release’s supported inspection/monitoring method.
7. Run a non-monetary acceptance suite: account creation, idempotent transfer submission, duplicate handling, failure/restart, node drain, a controlled replica loss and data/backup restore.
8. Only after finance controls approve: connect the finance-domain service, execute the four-record reconciliation test and retain the signed acceptance pack.

### 4.3 Upgrade, backup and recovery controls

TigerBeetle image changes are **controlled maintenance events**, not ordinary rolling application upgrades. Pin the binary image by immutable digest; test each selected release against a production-like cluster and financial invariant suite. Use the vendor’s version-specific upgrade/recovery instructions and a maintenance plan that covers quorum/failure constraints, backup verification, application client compatibility, change windows and rollback/recovery decision points. Never scale down the StatefulSet to change cluster size, delete PVCs during troubleshooting or re-run formatting against an existing volume.

Backups must be consistent with the selected TigerBeetle release’s supported recovery method, encrypted and copied outside the active failure domain. Every restoration exercise must include an independent sub-ledger-to-authorized-account reconciliation. If a financial posting differs, the platform opens a controlled reconciliation case; it does not overwrite the ledger or force a balance.

## 5. Mojaloop Deployment Procedure

### 5.1 Deployment posture

Mojaloop should be deployed as a controlled payment-interoperability subsystem, under a **pinned upstream Helm chart release** and a Ministry-owned overlay. Keep its service mesh/ingress configuration, external-payment connections, participant configuration and financial-operations SOPs separate from generic application releases. The upstream documentation describes deploying back-end dependencies, deploying the Mojaloop chart, validating ingress and executing test tooling; the implementation must translate those steps to the Ministry’s APISIX, Keycloak, open-appsec, GitOps and external-secret standards.[3]

| Layer | Deployment rule |
|---|---|
| Upstream chart | Pin chart version and image digests. Document the source repository, commit/release, values schema and supported Kubernetes range. Validate through a non-production full payment-simulator flow before promotion. |
| Backing services | Deploy required databases, Redis and other dependencies as separate, managed or independently charted releases with HA, backups, encryption, capacity and ownership. Do not rely on transient embedded development defaults. |
| API edge | External routes terminate through APISIX with mTLS/OIDC, schema validation, throttling, correlation IDs and open-appsec protection. Mojaloop admin/user interfaces are private. |
| Identity | Map Mojaloop participants/operators to Keycloak/approved federation. Apply MFA and segregation of duties for financial/operational administration. |
| Events and audit | Export approved events to Kafka via controlled adapters; preserve Mojaloop’s own audit/operational evidence under retention rules. |
| External participants | Onboard through sandbox, conformance, certificates, routing/limits, incident contacts, signed data-sharing/participation agreement and operational readiness. |

### 5.2 Deployment sequence

1. Approve the participant, settlement, liquidity, fraud/AML/sanctions, disputes, regulator reporting and incident-command operating model. Identify the authoritative legal records and reconciliation schedule.
2. Validate the selected Mojaloop version, official chart, required dependencies and all third-party components against the Ministry’s supported Kubernetes version and security baseline.
3. Provision `blueeco-mojaloop-prod`, dedicated node pools/resources and controlled backing-service releases. Restore/backup testing is required before Mojaloop deployment.
4. Install the Ministry overlay in a non-production environment using simulator/test participants. Use external secret references, private ingress and APISIX routes only.
5. Execute vendor-supported health checks plus Ministry contract tests: participant onboarding, quote/transfer lifecycle, duplicate/retry behavior, callback failures, certificate rotation, network outage, reconciliation output and audit export.
6. Conduct security testing of the ingress, API clients, administrative workflows, secrets and database access. Tune open-appsec in detection mode before managed prevention.
7. Promote immutable artifacts and reviewed values to production through GitOps. Run a controlled participant onboarding and end-to-end payment rehearsal with no live public fund exposure.
8. Authorize limited production traffic only after financial operations signs daily reconciliation, SOC/SRE signs monitoring/incident coverage and the responsible legal/regulatory authority confirms readiness.

### 5.3 Operational controls

Mojaloop’s availability must never be taken as proof of settlement completion. The finance domain reconciles: authorized institution account record; payment/provider state; TigerBeetle sub-ledger; and workflow/evidence record. An ambiguous state opens an exception workflow. The platform uses idempotency keys and provider status queries before retrying a transfer. Administrator accounts are individual, MFA-protected and subject to maker-checker roles; database access is emergency-only and audited.

## 6. Apache Sedona on Spark-on-Kubernetes

### 6.1 Deployment pattern

SedonaSpark runs as an application dependency in a Spark driver/executor job. The platform installs a supported Spark Operator in `blueeco-system` and applies `SparkApplication` resources into `blueeco-geo-prod`. Each application uses a version-pinned container image that includes a compatible Spark, Python, Sedona and required Delta/object-storage client stack. The job accesses data exclusively through approved catalog/object-store/Kafka endpoints and writes governed Delta tables, never arbitrary local or production application database storage.

| Workload | Examples | Scheduling pattern |
|---|---|---|
| Historical batch spatial ETL | Vessel trajectory normalization, port-call joins, lakehouse Silver transformations. | Scheduled `SparkApplication` with controlled resources and data-quality output. |
| Spatial analytics/data product | Corridor density, geofence/history, cold-chain journey exposure, fisheries aggregation. | On-demand or scheduled job; writes named Gold tables with lineage/quality metadata. |
| Reprocessing/backfill | Late telemetry correction, corrected source mapping, retained raw data replay. | Isolated job with approval, input/output version and cost budget. |
| Model feature preparation | Spatial features for Ray/Python modelling. | Versioned job with feature-set schema and model-register link. |
| Real-time spatial rule | Only after a concrete need is accepted; generally Flink/SedonaFlink evaluation. | Separate streaming design and state/replay acceptance, not part of initial Spark chart. |

### 6.2 Job lifecycle and controls

1. The data product owner publishes an input/output contract, classification, retention, quality SLO, expected cost/resource envelope and spatial coordinate reference system (CRS).
2. The job image is built from a signed, SBOM-producing pipeline and pinned by digest. Sedona, Spark, Delta and Python package versions are tested as a compatibility set.
3. A `SparkApplication` uses a dedicated service account and only the object-store/catalog/Kafka secrets or workload identity required. It cannot list Kubernetes Secrets, access finance namespaces or query transactional databases.
4. The driver writes job metadata, row counts, input/output Delta versions, quality result, spatial CRS and failure diagnostics to the governed operational/metadata store.
5. A job that fails a quality rule writes quarantine/error records, emits a `data_quality.failed` event and does not publish its Gold data product.
6. Jobs are resource-bounded through driver/executor requests/limits, node selectors, dynamic allocation policy, queue/priority policy and cost tags. Kubecost reports the expense by job, data product and domain.
7. Completed jobs clean ephemeral pods/data; governed result tables and logs are retained according to data/records policy.

### 6.3 Spark/Sedona release checklist

| Check | Required outcome |
|---|---|
| Version compatibility | Selected Sedona/Spark/Scala/Python/Delta/JDK versions pass integration test. |
| Geometry/CRS | Input/output CRS, precision, geometry validity and boundary semantics are documented and tested. |
| Object storage | Encryption, IAM, endpoint, bucket policy, transaction log and small-file compaction behavior pass test. |
| Security | Service-account/namespace and network policy deny unnecessary data/service access; no credentials baked into images. |
| Data quality | Expected schema, row-level rejects, late-data behavior, deduplication, lineage and quality thresholds are verified. |
| Reliability | Driver loss/retry behavior, executor loss, object-store transient failure and job re-run/idempotency are tested. |
| Cost/capacity | Jobs respect quotas; oversized geospatial joins have partitioning/spatial-index strategy and bounded cost estimate. |

## 7. Helm and GitOps Commands

The following sequence deliberately requires values files supplied by the approved environment pipeline. The commands fail immediately when any required path is absent; no example or synthetic deployment values are embedded in this repository. Perform every production action through the approved GitOps reconciler rather than an administrator workstation.

```bash
: "${TIGERBEETLE_VALUES_FILE:?approved TigerBeetle values file is required}"
: "${MOJALOOP_OVERLAY_VALUES_FILE:?approved Mojaloop overlay values file is required}"
: "${SEDONA_VALUES_FILE:?approved Sedona values file is required}"

helm lint charts/tigerbeetle --values "$TIGERBEETLE_VALUES_FILE"
helm template tigerbeetle charts/tigerbeetle \
  --namespace blueeco-tigerbeetle-prod \
  --values "$TIGERBEETLE_VALUES_FILE" > /tmp/tigerbeetle.rendered.yaml

helm lint charts/mojaloop-overlay --values "$MOJALOOP_OVERLAY_VALUES_FILE"
helm template mojaloop-overlay charts/mojaloop-overlay \
  --namespace blueeco-mojaloop-staging \
  --values "$MOJALOOP_OVERLAY_VALUES_FILE" > /tmp/mojaloop.rendered.yaml

helm lint charts/sedona-spark-jobs --values "$SEDONA_VALUES_FILE"
helm template sedona-spatial-jobs charts/sedona-spark-jobs \
  --namespace blueeco-geo-staging \
  --values "$SEDONA_VALUES_FILE" > /tmp/sedona.rendered.yaml
```

## 8. Production Acceptance, Monitoring and Decommissioning

| Service | Required acceptance evidence | Critical alert examples |
|---|---|---|
| TigerBeetle | Cluster formation and peer address verification; persistence/restart; fault/recovery test; backup restore; client idempotency; sub-ledger invariants; independent reconciliation. | Replica unavailable; disk latency/capacity threshold; peer communication failure; client request failure; backup failure; reconciliation break. |
| Mojaloop | Supported chart/version validation; ingress/route verification; simulator end-to-end tests; participant/certificate onboarding; retry/duplicate/error case; financial reconciliation; security/DR test. | Transfer/quote error spike; callback failures; dependency health; database/Redis saturation; certificate expiry; unmatched settlement/reconciliation break. |
| Sedona | Spark Operator health; signed image; data access test; data-quality gate; spatial validation; job retry; Delta restore/reprocess; quota/cost guardrail. | Driver/executor failure; quality rule failure; late-data/backlog; object-store errors; job queue saturation; abnormal cost/spend; unauthorized access denial. |

If a service is withdrawn or replaced, the Ministry retains: source/configuration; Helm values and Git history; SBOMs and licenses; audit and incident records; backups and defined data exports; operating procedures; test suites; container build definitions; data schemas; and a documented transition/reconciliation plan. Decommissioning may not delete statutory, financial, personal or security evidence before records, legal, privacy and operational owners approve the retention disposition.

## References

[1]: https://docs.tigerbeetle.com/operating/deploying/ "TigerBeetle Documentation — Deploying"
[2]: https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/ "Kubernetes Documentation — StatefulSets"
[3]: https://docs.mojaloop.io/technical/deployment-guide/ "Mojaloop Documentation — Deployment Guide"
[4]: https://sedona.apache.org/latest/ "Apache Sedona Documentation"

