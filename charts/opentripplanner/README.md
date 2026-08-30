# opentripplanner (OTP2) — Blue Economy Platform

OpenTripPlanner 2 multimodal trip-planning engine (Citizen Services
Advisory §5: door-to-door ferry + BRT + rail + walking planning, jetties
as interchanges, proto-MaaS open-data stance).

## Modes (render-gated)

- `mode=build` — a one-shot graph-build **Job** downloads the static GTFS
  bundle (`gtfs.staticUrl`, the geo-service feed factory
  `/feeds/gtfs.zip`) and an optional OSM PBF into the shared graph
  volume, then runs OTP `--build --save`. Serve pods block in a
  `wait-for-graph` init container until `graph.obj` appears.
- `mode=serve` — serve a prebuilt graph, either downloaded from
  `graph.url` per pod (emptyDir) or loaded from the persistence volume
  (`persistence.existingClaim` or the chart-managed PVC).

Both modes refuse to render without their required values (GTFS URL,
graph storage, downloader image, build resources).

## GTFS-RT updaters

`router-config.json` wires three OTP2 updaters against the geo-service
realtime endpoints — `vehicle-positions`, `stop-time-updater`
(TripUpdates) and `real-time-alerts`. All three URLs are REQUIRED. When
`gtfsRt.auth.enabled=true` the updaters send an `Authorization: Bearer`
header whose token is substituted by OTP2 from the `OTP_GTFS_RT_TOKEN`
environment variable (ExternalSecrets-synced; never inline).

## Metrics

OTP2 exposes Prometheus metrics only via the `ActuatorAPI` sandbox
feature (`/otp/actuators/prometheus`, Micrometer JVM + Jersey + GraphQL
timing). The ServiceMonitor render-refuses unless
`otpFeatures.actuatorApi=true`. Readiness uses
`/otp/actuators/health`, which returns 200 only once the graph is loaded
AND all updaters are ready.

## Honest OpenTelemetry statement

OTP2 (Java) has **no native OpenTelemetry instrumentation**. This chart
offers an opt-in (`telemetry.javaagent.enabled`, default OFF) upstream
OTel javaagent attached via an init-container shared volume and
`JAVA_TOOL_OPTIONS=-javaagent:...`:

- **What you get:** automatic JVM HTTP server/client spans and runtime
  metrics exported OTLP to the collector.
- **What you do NOT get:** routing-domain spans — the javaagent cannot
  see OTP's internal graph/Raptor search internals. Routing-algorithm
  visibility remains metrics/logs only. Do not represent this as full
  tracing coverage of the routing engine.

The chart render-refuses `telemetry.javaagent.enabled=true` without an
OTLP endpoint and a digest-pinned agent image.

## Frontend licence choice

The citizen web frontend is deployed by the sibling `trufi-planner`
chart, which packages the **OpenTripPlanner React UI**
(`opentripplanner/otp-react-redux`, MIT) rather than Trufi Core
(GPL-3.0, Flutter mobile) or digitransit-ui (EUPL-1.2 OR AGPL-3.0). See
that chart's comments for the full justification.
