# Geospatial stack deployment guide

Deploy order, per-environment checklist and verification posture for the
geo stack (GEO_ARCHITECTURE, approved Phase-5 design gate). All charts are
render-gated and cloud-agnostic per `docs/cloud-agnosticism.md`.

## Components and deploy order

```
1. postgis     charts/postgis          PostgreSQL 15 + PostGIS hot path
2. geo-service charts/geo-service      signed-envelope tracking API + ingest
3. martin      charts/martin           vector tiles (latest_positions,
                                       geofence_zones tile functions)
4. sedona jobs charts/sedona-spark-jobs batch lakehouse
               (vessel-trajectory-silver: bronze.vessel_observations ->
                silver.vessel_trajectories)
```

Why this order: geo-service runs the database migrations
(`db/migrations/0001..`: RANGE-partitioned `ais_positions`, `vessels_static`
SCD-2, `latest_positions`, `geofence_zones`, and the tile functions Martin
publishes), so PostGIS must exist first and Martin's tile functions only
exist after the geo-service migrations have run. Sedona jobs read the
lakehouse bronze layer fed by the bus, so they schedule last.

Supporting layers that must already be in place:

- `charts/dapr-components` (per-workstream pub/sub, state, secret stores)
- `charts/backup-dr` (WAL-G env ConfigMap the postgis backup wiring
  references: `backup.walGEnvConfigMapRef`, honouring `storage.provider`)
- `charts/cilium` with `networkPolicies.geo.enabled=true` (eBPF allows:
  geo-service ↔ postgis 5432, ↔ kafka 9092, ↔ redis 6379, ingress from the
  edge only; martin ↔ postgis only)
- `charts/apisix-routes` with `apisix.enabled=true` registering
  `geo-service` and `geo-martin` (Martin's render gate refuses to deploy
  without its registered edge route — Martin has no auth of its own)
- namespace `blueeco-geo-prod` from `kubernetes/base/namespaces`
  (restricted PSA + default-deny NetworkPolicy)

## Per-environment checklist

Values files live in the authorised environment repo
(`env/` template → `environments/<env>/<chart>.yaml`; see `env/README.md`).

### dev

- [ ] `postgis`: choose `image.variant` (`cloudnative-pg` if the CNPG
      operator is installed, else `postgis-image`), digest-pinned image,
      `storage.size`/`storageClass`, `credentialsSecretRef` (ExternalSecret
      synced), backup wiring to the backup-dr WAL-G ConfigMap.
- [ ] `geo-service`: `profile: dev`; `signing.convention: envelope` with
      dev signing keys in the secret store; `GEO_REPLAY_FILE` replay of
      recorded NMEA is permitted in dev only (documented provenance).
- [ ] `martin`: DSN secret for the `geo` role; `edge.routeRegistration.apisixRouteRef`
      pointing at the registered route.
- [ ] `sedona-spark-jobs`: sparkVersion, quality contract, network CIDRs.
- [ ] Kafka TLS/SASL optional (dev fixtures default off).

### staging

- [ ] Same as dev, with `profile: staging`, staging endpoints/sizing, and
      the live-verification evidence below recorded for promotion.

### prod

- [ ] `geo-service profile: prod` — render gate refuses any `GEO_TEST_*`
      env and `GEO_REPLAY_FILE` (no simulated feeds in production).
- [ ] `pubsub.kafka.tls.required=true` and `geo-service kafka.tls.required=true`
      (gap #7 prod posture); SASL mechanism `scram-sha-512` preferred.
- [ ] Signing keys from the prod secret-store backend; epoch tracked.
- [ ] PostGIS storage sized for RANGE-partitioned positions with BRIN/GiST
      indexes; backup immutability matches the regional-dr contract.
- [ ] HPA enabled (`geo-service hpa.enabled=true`) with reviewed bounds.

## Verification posture (honest note)

The Cilium `CiliumNetworkPolicy` resources (`charts/cilium
templates/geo-policies.yaml`), the `ApisixRoute` CRs
(`charts/apisix-routes`), the CloudNativePG `Cluster` CR and the
SparkApplication CR are **render-validated** against their approved CR
shapes in CI (`scripts/validate-manifests.sh`, helm template + lint), but
they have **not yet been applied to a live cluster**. First-live-cluster
verification (W4 of the GEO_ARCHITECTURE wave plan) must confirm:

1. The Cilium geo policies select the intended endpoints (Hubble flow
   evidence: geo-service→postgis/kafka/redis allowed, everything else
   dropped; martin→postgis only).
2. APISIX accepts the ApisixRoute CRs (geo-service, geo-martin,
   ministry-portal, cvffapi, admin) with the OPA hook evaluating
   `blueeconomy/http/allow` and bearer-only OIDC.
3. The postgis variant chosen per environment comes up with PostGIS 3.x
   extensions and WAL-G archiving to the backup-dr store.
4. Martin publishes `latest_positions` / `geofence_zones` only after the
   geo-service migrations create those functions.

Until that evidence lands, treat these resources as design-complete,
runtime-unverified.
