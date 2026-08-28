# Blue Economy Platform GitOps

This repository contains non-secret Kubernetes policy, source locks and deployment-source declarations for the hybrid Blue Economy Platform. It does not contain a kubeconfig, cloud credentials, partner endpoints, certificates, TLS private keys, runtime secrets, fabricated environment values or production data.

The platform is **cloud-agnostic and sovereign-deployable**: it runs on any Kubernetes >= 1.29 — on-prem/self-hosted clusters, sovereign clouds, or commercial clouds. Provider-specific services appear only as pluggable, render-gated options behind provider-neutral abstractions, never as hard requirements; Azure Government remains a fully-supported landing-zone option. The component-by-component provider-neutrality contract is `docs/cloud-agnosticism.md`.

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
  pluggable secret stores: Kubernetes, Azure Key Vault, HashiCorp Vault or
  an operator-managed external ClusterSecretStore). Rendered once per workstream
  with scopes restricted to that workstream's app-ids; every release is
  hard-restricted to its own approved app-ids (cvff fiduciary segregation,
  isr national-security segregation).
- `charts/beneficiary-portal` — CVFF beneficiary self-service web portal
  (static SPA behind the APISIX edge, TLS-only ingress, read-only root
  filesystem). OIDC discovery is served via a ConfigMap-backed
  `platform-config.json` pointing at the `beneficiary-portal` PKCE public
  client of the cvff realm; no secret material exists in the workload.
- `charts/temporal` — Temporal server plus bootstrap Job registering the
  `cvff`, `ecallup` and `ferry` workflow namespaces; worker Deployments are
  wired in the service charts.
- `charts/keycloak-realms` — the six workstream realms (ports, ferries,
  cvff, seafarer, fisheries, isr) with the approved role catalogues,
  enforced short-TTL token policy (access token lifespan ≤ 300 s),
  confidential service clients delivered via ExternalSecrets (realm JSON
  uses the leave-unchanged secret sentinel) and PKCE-S256 public clients
  (beneficiary-portal on the cvff realm, blueeconomy-mobile on the five
  user-facing realms) with exact-match redirect-URI allowlists.
- `kubernetes/base/namespaces/{ports,ferries,cvff}.yaml` — workstream
  namespaces with restricted PSA and default-deny NetworkPolicies; cvff
  additionally denies cross-workstream ingress.
- Observability pins (Prometheus, OpenTelemetry Collector, OpenSearch) in
  `components/upstream-components.lock.yaml`.
- Provider-neutrality contract (cloud-agnostic, sovereign-deployable):
  `docs/cloud-agnosticism.md`. Landing-zone option guides:
  `docs/azure-government-landing-zone.md` (Azure Government / AKS — one
  fully-supported option, not the assumed target).

## Battle-hardened edge and recovery layer

Closes the three structural gaps from the platform security posture review
(edge/DDoS designed but not deployed, event-bus signature key distribution,
DR contract without machinery):

- `charts/cilium` — values wrapper and release contract for the pinned
  upstream Cilium CNI: kube-proxy replacement, Hubble flow observability
  (relay + UI), Tetragon runtime enforcement (process-exec and
  file-integrity TracingPolicies for tigerbeetle, financial-controls and
  keycloak pods), per-workstream L3/L4 CiliumNetworkPolicies (default-deny
  plus explicit allows mirroring the Dapr app-id scope model; TigerBeetle
  egress is render-gated to the cvff workstream only), L7 HTTP-aware
  policies for the ingress path, and standalone XDP-accelerated
  LoadBalancer DDoS mitigation. Node kernel baseline (>= 5.4, no io_uring
  requirement) is render-gated.
- `charts/caddy` — Caddy TLS-terminating edge in front of APISIX, promoted
  from the umbrella design-stage kustomize: automated TLS via a
  provider-neutral issuance enum (ACME DNS-01 via rfc2136/azuredns/
  route53/cloudflare/googleclouddns/digitalocean, cert-manager internal-ca,
  operator-supplied manual certificates, or the platform-internal CA), the
  promoted security-header set, request-size/timeout caps, edge mTLS for
  partner/NSW routes, the OpenAppSec WAF contract flag (render gate refuses
  to disable it) and the OIDC relying-party contract for admin consoles.
  Integration topology: `docs/edge-topology.md`.
- `charts/opa-policies` — reconciled OPA layer promoted from the umbrella
  seed: the platform policy packs (`http.rego` edge hook, `cvff.rego`
  four-party SoD, `admin.rego` tenant scoping, `clearance.rego`
  classification gating) in an immutable ConfigMap, the OPA server, the
  APISIX opa-plugin hook contract, and the producer-signature key directory
  (Ed25519 public keys for all eight platform producers, render-gated —
  no key material is defaulted or fabricated) consumed by
  security-operations and data-platform via `KEY_DIRECTORY_PATH` mount.
- `charts/backup-dr` — DR machinery fulfilling the `charts/regional-dr`
  contract: Velero scheduled cluster backups (pinned upstream release
  contract + reconciled Schedule/BackupStorageLocation CRs), WAL-G
  continuous Postgres archiving to immutable S3-compatible/ADLS storage
  (`immutabilityDays` render-gated equal to the regional-dr contract), a
  CronJob restore-test harness, and the restore runbook
  `docs/dr-restore.md`.
