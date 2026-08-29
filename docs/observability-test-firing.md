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
