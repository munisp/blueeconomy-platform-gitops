# blueeconomy-platform-env — environment values layout (template)

This directory is the **in-repo template** for the separately deployed
`blueeconomy-platform-env` repository (the authorised environment-values
repo referenced by `gitops/argocd/applicationset.yaml` as the multi-source
`$values` ref: `https://github.com/munisp/blueeconomy-platform-env.git`).
Copy this layout into that repository and replace every `REQUIRED_*`
placeholder with approved environment values.

The separation is deliberate: this GitOps repo carries fail-closed charts
and policy; the env repo carries the approved, per-environment values
(registry names, digests, secret-store references, endpoints, CIDRs). Until
the env repo supplies values, every Argo CD Application surfaces the
charts' render gates instead of deploying — that is intentional.

## Layout

```
environments/
  dev/      <chart>.yaml   # one file per ApplicationSet entry
  staging/  <chart>.yaml
  prod/     <chart>.yaml   # consumed by the ApplicationSet as
                           # $values/environments/prod/<chart>.yaml
```

One values file per ApplicationSet element, named after the chart
(`postgis.yaml`, `martin.yaml`, `geo-service.yaml`, `apisix-routes.yaml`,
`dapr-components.yaml`, …). The six per-workstream `dapr-components`
Applications share the single `dapr-components.yaml` for the environment;
the workstream is pinned by the ApplicationSet `workstream` parameter, and
the charts hard-refuse a workstream's release scoped to foreign app-ids.

## What belongs in a values file

Exactly the chart's render-gated values, and nothing else:

- `image.repository` / `image.digest` — approved registry host and the
  immutable `sha256:` digest (never a mutable tag).
- `externalSecrets.storeRef.name` — the landing zone's secret backend
  ClusterSecretStore (any ESO-supported provider; see
  `docs/cloud-agnosticism.md`).
- Provider-enum selections and their required settings (e.g.
  `postgis image.variant`, `backup-dr storage.provider`,
  `caddy tls.acme.dnsProvider.name`).
- Endpoints, CIDRs, namespaces, cron schedules and resource sizing approved
  for the environment.

Secrets themselves NEVER live here: only ExternalSecrets remote refs and
Secret names.

## Promotion flow (dev → staging → prod)

1. Land the chart change in this GitOps repo with CI render fixtures and
   negative gates green (`scripts/validate-manifests.sh`).
2. Fill `environments/dev/<chart>.yaml`; sync the dev Argo CD instance;
   run the live verification checklist (see `docs/geo-deployment.md` for
   the geo stack).
3. Promote the same values to `environments/staging/<chart>.yaml`,
   adjusting only environment-specific endpoints/sizing; re-verify.
4. Prod promotion is a reviewed PR against `environments/prod/` carrying
   the staging evidence; prod-only gates (e.g.
   `pubsub.kafka.tls.required=true`, `geo-service profile: prod` refusing
   `GEO_TEST_*`) must hold. Approval = merge; Argo CD syncs.
5. Rollback = revert the env-repo PR (Application `revisionHistoryLimit`
   and automated `selfHeal` keep the previous approved values converged).

## Environment differences that must stay explicit

- `dev` may use the `dev`/`staging` profiles and dev fixtures (e.g.
  `GEO_REPLAY_FILE` recorded-NMEA replay, clearly namespaced); `prod` is
  render-gated against them.
- Kafka TLS/SASL: optional in dev fixtures, `tls.required=true` in prod
  (gap #7).
- Signing: exactly one `signing.convention` per service (envelope for new
  services; `docs/signing-config.md`).
