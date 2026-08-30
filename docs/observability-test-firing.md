# Observability alert test-firing runbook (OTEL_DESIGN.md §4 gate 4)

The production gate requires: **a test alert fires in Prometheus and a
Novu notification lands**. This is the acceptance procedure for the
Prometheus -> Alertmanager -> Novu chain; run it in staging before the
first production enablement and after every change to
`charts/alertmanager`, `charts/novu` or `charts/prometheus-rules`.

## Procedure

1. Confirm the chain is up: Prometheus scrapes `up{service=~".*(tempo|loki|alertmanager|novu-api|otel-collector-gateway).*"}` == 1
   (also the `*Down` rules' negative condition).
2. Fire a synthetic alert at Prometheus (approved operator action):
   `promtool`-style static series or a temporary always-true rule
   (`vector(1)`) labelled `service: otel-collector`,
   `severity: warning` in a scratch PrometheusRule; OR use
   `amtool`/`curl` to POST a test alert directly to Alertmanager
   (`/-/api/v1/alerts`) with the same labels.
3. Verify the alert appears in Alertmanager
   (`http://<alertmanager>:9093/#/alerts`) grouped by
   `alertname, service, severity` after `group_wait` (30s).
4. Verify Alertmanager POSTs to the Novu webhook receiver
   (`novu.webhookUrl`; check the alertmanager log for a 2xx and the
   Novu api log for the inbound trigger event).
5. Verify the Novu workflow delivers the notification to the approved
   ops channel (email/SMS/Telegram-class per the workflow config) and,
   on `send_resolved`, that resolution closes the loop.
6. Remove the synthetic rule/alert and record the evidence (screenshots
   / API responses) in the wave acceptance report.

## Notes

- Alertmanager routes EVERY alert to Novu (`route.receiver: novu`,
  `routes: []`); a missing notification therefore means the Novu
  webhook path or workflow is broken — never assume "no alerts".
- The Novu chart is NOT_RUN (env contract follows the community
  self-host reference): step 4/5 double as its first live validation.
- Keep the synthetic rule out of any committed overlay: test-firing is
  an operator action, not a standing manifest.

## Novu live-fire prerequisites (W-OPS1 feasibility assessment)

Novu has never been executed against a live cluster (NOT_RUN). A live
test-fire is feasible in staging; it requires ALL of the following,
none of which the charts can provision or validate for you:

1. **MongoDB** (workflows/subscribers/events persistence) reachable
   from the Novu namespace. The chart render-gates
   `dataStores.mongodb.host` and refuses any render whose `secretEnv`
   drops `NOVU_MONGO_URL` (the `mongodb://` URI incl. credentials,
   synced via ExternalSecrets) — a prod render without the MongoDB URI
   fails closed at render time, never at pod startup.
2. **Redis** (queues/cache) reachable from the Novu namespace.
   Render-gated: `dataStores.redis.host` plus the mandatory
   `NOVU_REDIS_PASSWORD` secretEnv entry (same refusal class as above).
3. **Workflow + credential bootstrap.** Alertmanager's receiver posts to
   the Novu api inbound-trigger URL (`novu.webhookUrl` in
   charts/alertmanager, render-gated). That URL only exists once the
   alert-intake workflow has been created in Novu, and the workflow's
   delivery channels need provider credentials — none of which exists on
   a FRESH Novu install. Bootstrap order: (a) deploy Novu with a
   pipeline-generated initial `NOVU_API_KEY` in the external secret
   store (the chart render-gates it via the mandatory `secretEnv`
   contract); (b) verify the Novu api pod is Ready and the dashboard
   login works; (c) create the alert-intake workflow in the Novu
   dashboard (or via the platform API with the bootstrap key) with the
   approved ops channel (email/SMS/Telegram-class) and its provider
   credentials; (d) only then set `novu.webhookUrl` to the workflow's
   inbound-trigger URL and run the test-firing procedure above. Whether
   the approved Novu version requires an Authorization header on the
   inbound trigger is an open doc-check at enablement (the Alertmanager
   webhook receiver cannot add custom headers — if the trigger requires
   auth, front it with the edge or use a signed trigger URL per that
   version's docs).
4. **Remaining honest unknowns** (community self-host contract, not yet
   verified against a running instance): the exact per-service command
   layout (`apps/api|worker|ws|web/dist/main.js`) and env surface of
   the approved upstream Novu image version must be confirmed against
   that version's self-host docs at first enablement; the startup/
   readiness probes are TCP-level (an HTTP `/health` path is not
   asserted until verified live); the `ws` and `web` services'
   ingress/CORS posture for the dashboard is landing-zone policy.

Record the first live run's evidence (Novu api logs, workflow delivery
receipts, Alertmanager 2xx) in the wave acceptance report and update
this runbook with any contract corrections — do NOT amend the chart's
NOT_RUN honesty note until that evidence exists.
