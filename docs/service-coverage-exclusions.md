# Service coverage exclusions (GAP-PG-01/GAP-PG-03 review)

Every deployable platform service is expected to be reconciled through
this repository (chart + ApplicationSet entry + environment overlays).
The following repositories were reviewed for the Phase-7 manifest gap
remediation and are **deliberately excluded** from the deploy surface
because they ship no server component. This document is the exclusion
record; if either repository grows a runtime, the exclusion must be
revisited and a chart added instead.

## blueeconomy-maritime-evidence — Go library + migration CLI (no server)

Evidence: the repository's only binary is `cmd/evidence-migrate`
(a bounded, approval-gated legacy-S3 migration helper that requires
`EVIDENCE_MIGRATION_APPROVED=true` and an explicit `--dry-run|--apply`
mode). There is no `http.Server` anywhere; the README states the repo
"does not claim that an evidence API ... is live". It is consumed as a
Go package plus DBA-applied SQL migrations (`db/migrations/`), which the
approved migration process owns — wrapping it in a Kubernetes Job with
the approval env baked in would defeat the two-person migration gate.
No health endpoints, no metrics surface, nothing to reconcile.

## blueeconomy-mobile — React Native client application (no server)

Evidence: the repository is an Expo/React Native client (`App.tsx`,
`app.config.ts`, `eas.json`) built and distributed through EAS; it
contains no HTTP server, listener or long-running process. Client
observations reach the platform exclusively through the published API
edge (APISIX routes in `charts/apisix-routes`), so there is no
cluster-side workload to deploy.

## Previously excluded (standing record)

- `blueeconomy-contracts` — buf/protobuf message contracts + generated
  stubs; no runtime.
- `blueeconomy-developer-platform` — documentation and scripts only.
- `singlewindow` — ships its own in-repo `helm/` chart (tradegateway);
  the platform edge integrates it, gitops does not re-render it.
- `blueeconomy` — programme umbrella (docs/governance/meta).
