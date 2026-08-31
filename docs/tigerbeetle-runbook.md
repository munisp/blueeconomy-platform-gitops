# TigerBeetle Operations Runbook

Operational procedures for the Ministry-owned TigerBeetle ledger cluster
deployed from `charts/tigerbeetle`.

**Validation status: render-validated only.** Every procedure in this
document is derived from the chart's rendered manifests and the upstream
TigerBeetle documentation. No live cluster exists in this repository's
gate environment, so these procedures have **not** been executed against a
running TigerBeetle cluster. Before production use, each procedure must be
exercised once in an approved staging environment and the evidence
retained (see `docs/dr-restore.md` for the drill-evidence contract).

## 1. Replica topology

- The ledger runs as a `StatefulSet` (`OrderedReady`, headless service
  `<release>-tigerbeetle-headless`) with `tigerbeetle.replicaCount`
  replicas. The approved production topology is **6 replicas** (chart
  default); the minimum for quorum-safe rolling maintenance is 3.
- Replica identity is the StatefulSet ordinal. Peer addresses are rendered
  from `tigerbeetle.peerAddressTemplate` as the ordered ordinal DNS names;
  the template must never be changed after the cluster is formatted.
- `tigerbeetle.clusterID` is **PROTECTED**: it is formatted into the data
  file. Changing `clusterID`, `replicaCount`, or the peer address template
  against an existing data directory is unsupported and will strand data.
- Each replica holds a full copy of the ledger in
  `tigerbeetle.dataPath` (`/var/lib/tigerbeetle/data.tigerbeetle`) on its
  own PVC (`data-<release>-tigerbeetle-<ordinal>`). PVCs are **retained**
  on delete and on scale-down
  (`persistentVolumeClaimRetentionPolicy: Retain/Retain`); they must never
  be deleted automatically.
- Scheduling: pod anti-affinity (one replica per node) and zone
  topology-spread (`DoNotSchedule`) are mandatory; a
  `PodDisruptionBudget` (`maxUnavailable: 1`) protects quorum during
  voluntary disruption.

## 2. Safe rollout and restart

The StatefulSet uses `RollingUpdate` with `partition: <replicaCount>`,
so **no pod is ever restarted by the controller without an explicit
operator action**.

Rolling restart / image-upgrade procedure (one replica at a time):

1. Confirm cluster health: all replicas Ready, and (with a client or the
   approved exporter) confirm a quorum is committing. Never proceed with
   fewer than `replicaCount - 1` healthy replicas.
2. Lower the partition by one: `partition = replicas - 1 - <ordinal>`,
   then delete the highest-ordinal pod
   (`kubectl delete pod <release>-tigerbeetle-<n-1>`).
3. Wait for the pod to rejoin: Ready probe green **and** the replica has
   caught up (its commit offset tracks the quorum — check via the approved
   metrics exporter or a read-only client query).
4. Repeat for ordinals n-2 … 0, lowering the partition each time.
5. After the last replica, verify quorum health and client traffic before
   closing the change.

Never restart two replicas concurrently; with 6 replicas the loss of a
second replica during a restart still leaves quorum (4/6), but the margin
for a concurrent failure is gone.

## 3. Data-directory recovery

The init container (`format.sh` in the `<release>-tigerbeetle-init`
ConfigMap) **refuses to format a non-empty data file** — an existing data
directory is always preserved, never silently re-initialized.

- **Replica data loss with the PVC intact:** simply restart the pod. The
  init container detects the existing file and skips formatting; the
  replica recovers from its last checkpoint and replicates forward from
  the quorum.
- **PVC lost / node loss:** create a replacement PVC (same name, same
  storage class) or let the StatefulSet recreate it empty; the init
  container formats a fresh data file for that ordinal and the replica
  re-syncs in full from the quorum. This is safe only while the remaining
  replicas hold quorum.
- **Whole-cluster loss:** restore one replica's data file from the
  immutable object-storage backup (section 5), then let the other
  replicas re-sync from it. Whole-cluster restore is a DR procedure —
  follow `docs/dr-restore.md` and record the evidence.
- Before any recovery, verify with `tigerbeetle inspect` (for the deployed
  TB version) that the restored data file is consistent. **NOT_RUN:** the
  exact `inspect` invocation for the approved release must be validated in
  the restore drill before reliance.

## 4. Replica rejoin after OOM (dev posture)

**Honest dev posture: TigerBeetle stays DOWN on small dev boxes.** The
chart requests 8 GiB and limits 16 GiB per replica (production sizing);
TigerBeetle preallocates and memory-maps its data file and does not
tolerate being sized below its working set. On development clusters that
cannot honour the requests, the kernel OOM-kills the replica on startup
and the pod enters `CrashLoopBackOff` (OOMKilled). This is expected and
accepted for dev: **do not** work around it by lowering requests/limits
below the approved floor in shared values — dev environments simply run
without the ledger, and finance-dependent flows are stubbed or pointed at
an approved shared environment.

When a replica is OOM-killed on a properly sized node:

1. Confirm the OOM kill: `kubectl describe pod` shows `OOMKilled`; check
   node memory pressure.
2. TigerBeetle restarts and rejoins automatically: the init container
   skips formatting (data file present), and the replica catches up from
   the quorum. No operator action is needed for a single OOM.
3. If OOM recurs, treat it as a capacity fault: check that no memory-hog
   co-tenant landed on the `financial-stateful` node pool (the node
   selector and anti-affinity should prevent this), and that the data
   file size is within the approved growth envelope. Escalate for a
   resize change rather than restarting repeatedly.
4. A replica that is OOM-looped for a long period may lag; after it
   stabilizes, verify catch-up before restarting any other replica.

## 5. Backup coordination with charts/backup-dr

- The chart's optional `backup.enabled` flow (GAP-PG-05) takes a
  crash-consistent `VolumeSnapshot` of one redundant replica's PVC
  (default ordinal 5), streams the gzip-compressed data file plus a
  sha256 manifest to the immutable object-storage bucket, and cleans up
  scratch resources. TigerBeetle checksums every sector and recovers from
  the last consistent checkpoint on restore, so crash-consistent
  snapshots are the upstream-documented backup model.
- **NOT_RUN:** this flow is render-gated but has never executed against a
  live cluster. Enable only after an approved restore drill
  (`charts/backup-dr` `restoreTest` harness plus
  `scripts/backup-drill.sh` / `scripts/restore-drill.sh`) validates
  snapshot restore and replication catch-up for the deployed version;
  evidence lands in `docs/dr-restore.md`.
- Coordination rules:
  - The backup replica ordinal must be `< replicaCount` and must not be
    concurrently restarted (align the backup schedule — default `0 2 * *
    *` — away from maintenance windows).
  - The storage target must satisfy the `charts/backup-dr` immutability
    contract (S3 Object Lock / immutable blob policy) with the same
    `immutabilityDays` as the regional-dr recovery contract.
  - Credentials reach the backup Job only via an ExternalSecrets-synced
    Secret (`backup.storage.credentialsSecretRef`); no credential
    material ever enters this repository.
  - Velero schedules in `charts/backup-dr` complement (do not replace)
    the data-file backup: Velero captures the namespace objects, the TB
    backup captures the ledger itself.

## 6. Upgrade procedure

1. Pin the new image by immutable digest (`image.digest`) after SBOM,
   vulnerability and compatibility approval; never upgrade by tag.
2. Confirm upstream TigerBeetle release notes allow a rolling upgrade
   between the two versions (replica protocol compatibility).
3. Take a manual ledger backup (section 5 flow) immediately before the
   upgrade and retain it beyond the change window.
4. Roll one replica at a time using the partition procedure in section 2,
   starting from the highest ordinal. After each replica, verify rejoin
   and catch-up before continuing.
5. If a replica fails to start on the new version, roll that replica back
   to the previous digest (same partition procedure) and halt the
   upgrade; do not run a mixed-version cluster longer than the upgrade
   window.

## 7. Monitoring and alerts

- TigerBeetle serves no HTTP metrics endpoint. Metrics require an
  approved exporter/sidecar; the chart refuses a `ServiceMonitor` unless
  `monitoring.metricsPort` names the approved exporter port (render gate).
- Minimum alert set (to be wired in the approved environment's Prometheus
  rules; thresholds to be tuned in staging):
  - **Replica down**: fewer than `replicaCount` Ready pods for > 5 min.
  - **Quorum at risk**: fewer than `replicaCount - 1` Ready pods — page
    immediately; halt all maintenance.
  - **OOMKilled restart**: any restart with reason `OOMKilled` (see
    section 4).
  - **PVC pressure**: data volume > 80% of `persistence.size`.
  - **Backup freshness**: no successful backup object in the immutable
    bucket within 25 h of the schedule.
- The startup probe allows 5 minutes (60 × 5 s) for a replica to open its
  data file and begin listening; alert on startup-probe failures only
  after that window.
