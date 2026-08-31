# DR Restore Runbook

Scope: recovery of the BlueEconomy platform from the `charts/backup-dr`
machinery (Velero scheduled cluster backups + WAL-G continuous Postgres
archiving) in fulfillment of the `charts/regional-dr` recovery contract
(active-passive, manual-approved failover with >= 2 approvers,
`immutabilityDays > 0`, restore-drill freshness).

Render-gate alignment: `charts/backup-dr` refuses to render unless
`backup.immutabilityDays` equals the approved
`regionalDR.backup.immutabilityDays` — the machinery cannot drift from the
contract.

## 0. Preconditions

- Failover approval recorded per the regional-dr contract
  (`failover.mode: manual-approved`, `minimumApprovers >= 2`,
  `approvalEvidenceRef`). Do not begin a production failover without it.
- Recovery cluster: distinct region and cluster from the primary
  (contract-enforced), platform base applied
  (`kubernetes/base`, Argo CD pointing at this repository).
- Backup storage credentials synced into the recovery namespace via the
  approved ExternalSecrets path (the landing zone's secret store).
- The immutable backup store (S3 Object Lock / Azure Blob immutable policy,
  retention = `immutabilityDays`) is readable from the recovery region.

## 1. Assess and select the restore point

1. List Velero backups: `velero backup get` — choose the latest
   `Completed` backup from the affected schedule; record its name in the
   change record.
2. Verify WAL-G archive continuity for each Postgres cluster:
   `wal-g backup-list` and `wal-g wal-show` against the archive prefix. If
   the primary failed mid-transaction, the RPO is bounded by the WAL
   archive, not the last base backup.
3. Confirm the chosen restore point satisfies the contracted
   `rpoMinutes`. If not, escalate — do not silently accept a stale point.

## 2. Restore cluster state (Velero)

```
velero restore create <restore-name> \
  --from-backup <backup-name> \
  --storage-location <release>-backup-dr-primary \
  --wait
```

- Restore order: platform namespaces (`blueeconomy-platform`,
  `blueeconomy-security`) first, then workstreams, then
  `blueeco-tigerbeetle-prod` last (it must never accept traffic before its
  peers are consistent).
- A restore completing `PartiallyFailed` is a failed restore: investigate
  before proceeding; do not route traffic.

## 3. Restore Postgres to the WAL archive edge (WAL-G)

For each cluster in `walG.clusters`:

1. Restore the latest base backup into the cluster's data directory:
   `wal-g backup-fetch <pgdata> LATEST`.
2. Create `recovery.signal` with
   `restore_command = 'wal-g wal-fetch %f %p'` so Postgres replays archived
   WAL to the last durable segment.
3. Start Postgres and confirm recovery completion
   (`pg_is_in_recovery()` returns false).
4. Run the sentinel checks: evidence package count, CVFF approval count,
   and a TigerBeetle replica availability probe. Compare against the
   pre-incident evidence where available.

## 4. Reconcile and cut over

1. Verify Argo CD applications are `Synced`/`Healthy` on the recovery
   cluster.
2. Run the restore-reconciliation drill script
   (`scripts/run-restore-reconciliation-drill.sh`) and attach its output to
   the change record.
3. Flip routing to the secondary endpoint per the regional-dr routing
   contract (`failoverRecordRef`) — only after steps 1–3 are green and the
   second approver has countersigned.
4. Record the drill/failover evidence at the contracted
   `drill.evidenceLocationRef` (satisfies `restoreDrillMaxAgeHours`).

## 5. Restore-test drill (standing)

The `charts/backup-dr` restore-test CronJob continuously exercises stages
1–4 of section 2/3 against an ephemeral namespace and writes drill-evidence
ConfigMaps. Review its history weekly; a missed or failed drill breaches
the regional-dr `restoreDrillMaxAgeHours` freshness gate and must be
treated as a recovery-readiness incident.

## 6. Failback

Failback is a fresh failover in the opposite direction: same approvals,
same machinery, with the recovered region re-seeded from the immutable
store. Never fail back onto unreconciled state.
