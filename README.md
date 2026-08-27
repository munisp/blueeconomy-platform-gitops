# Blue Economy Platform GitOps

This repository contains non-secret Kubernetes policy, source locks and deployment-source declarations for the hybrid Blue Economy Platform. It does not contain a kubeconfig, cloud credentials, partner endpoints, certificates, TLS private keys, runtime secrets, fabricated environment values or production data.

The current base applies namespace boundaries and policy source. The `charts/` directory now versions the Ministry-owned TigerBeetle StatefulSet pattern, the Mojaloop release-control overlay, the Sedona Spark job pattern and a disabled-by-default umbrella chart. Each service chart fails rendering when required approved environment values are absent. No example values are supplied because the Ministry environment registry, immutable image digests, infrastructure identifiers and regulated authorities have not been provided.

A source lock, successful lint or rendered manifest is **not** evidence of deployment. A deployment is verified only when an authorized hybrid target, reviewed environment values, change approval, target-side health and security evidence, recovery testing and the applicable business acceptance record are all retained. See `docs/core-services-deployment-guide.md` and `policies/core-services-production-guardrails.md`.

Run the local source validation with:

```bash
bash scripts/validate-manifests.sh
```

## Shared-platform deployment layer

The repository is reconciled by **Argo CD** (`gitops/argocd/`, pinned in
`components/upstream-components.lock.yaml`; see `docs/gitops-controller-argocd.md`).
The shared-platform layer adds:

- `charts/ferry-ticketing`, `charts/port-interoperability`,
  `charts/financial-controls`, `charts/security-operations` — workstream
  service charts (fail-closed values, digest-pinned images, restricted PSA,
  default-deny NetworkPolicies, ExternalSecrets-only credentials, Dapr sidecar
  annotations, per-workstream ServiceMonitor/PodMonitor).
- `charts/dapr-components` — per-workstream Dapr components (Kafka pub/sub
  with documented Fluvio variant, Redis hot + PostgreSQL durable state,
  Kubernetes + Azure Key Vault secret stores). Rendered once per workstream
  with scopes restricted to that workstream's app-ids; the cvff release is
  hard-restricted to cvff app-ids (fiduciary segregation).
- `charts/temporal` — Temporal server plus bootstrap Job registering the
  `cvff`, `ecallup` and `ferry` workflow namespaces; worker Deployments are
  wired in the service charts.
- `charts/keycloak-realms` — the three workstream realms with the approved
  role catalogues, enforced short-TTL token policy (access token lifespan
  ≤ 300 s) and confidential service clients delivered via ExternalSecrets
  (realm JSON uses the leave-unchanged secret sentinel).
- `kubernetes/base/namespaces/{ports,ferries,cvff}.yaml` — workstream
  namespaces with restricted PSA and default-deny NetworkPolicies; cvff
  additionally denies cross-workstream ingress.
- Observability pins (Prometheus, OpenTelemetry Collector, OpenSearch) in
  `components/upstream-components.lock.yaml`.
- Azure Government / AKS landing-zone assumptions:
  `docs/azure-government-landing-zone.md`.
