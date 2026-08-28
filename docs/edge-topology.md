# Edge Integration Topology

Status: reconciled design. Caddy is Argo-managed via `charts/caddy`; APISIX,
Keycloak and the OpenCTI/Wazuh stack remain source-locked upstreams
(`components/upstream-components.lock.yaml`) until their deployment gates are
approved. This document is the authoritative statement of what each layer
enforces.

## Request path

```
client (browser / mobile / USSD / partner authority)
  → Caddy edge            (charts/caddy, namespace blueeconomy-security)
  → OpenAppSec WAF agent  (contract flag; agent inside the APISIX pod)
  → APISIX gateway        (source-locked upstream, blueeconomy-security)
  → Dapr sidecar mesh     (charts/dapr-components, per-workstream scopes)
  → workstream services   (blueeconomy-{ports,ferries,cvff,seafarer,fisheries,isr})
```

L3/L4 below this path is closed by `charts/cilium`: default-deny
CiliumNetworkPolicies per workstream namespace, an L7 HTTP-aware policy chain
for exactly the two ingress hops (Caddy→APISIX, APISIX→workstream pods), and
standalone XDP-accelerated LoadBalancer nodes absorbing volumetric/SYN floods
before traffic reaches the edge pods.

## Per-layer enforcement

### 1. Caddy edge (`charts/caddy`)

- TLS termination only; every listener is HTTPS with the promoted security
  header set (HSTS preload, nosniff, frame DENY, no-referrer, restrictive
  Permissions-Policy, `Server` stripped).
- Automated certificate issuance: ACME DNS-01 through the Azure DNS solver
  abstraction (Azure Government compatible; credentials arrive only via the
  ExternalSecret from Azure Key Vault) or the platform-internal CA
  (`tls.mode: internal`).
- Edge mTLS `require_and_verify` for `/partner/*` and `/v1/nsw/*` against the
  approved partner CA bundle — authority/NSW traffic cannot cross the edge
  without a partner client certificate.
- Coarse abuse controls: request-body cap (render-gated ≤ 2MB), proxy
  read/write timeouts, and a coarse per-remote-host rate limit
  (render-gated ≤ 60/min) on `/v1/*`. Fine-grained, identity-aware limiting
  is deliberately left to APISIX.
- Separate admin listener hostname, reachable only from the management
  network (landing-zone LB enforcement), proxying the APISIX admin upstream.
- The Caddyfile is rendered from render-gated values; the umbrella
  `${VAR}` placeholder kustomize is superseded by this chart.

### 2. OpenAppSec WAF (contract flag)

- Asserted by `openappsec.required: true` in `charts/caddy`, mirroring the
  existing fail-closed contract flag in
  `charts/mojaloop-overlay/templates/000-validation.yaml`. Both render gates
  refuse to disable it.
- Deployment shape (per the contract): the OpenAppSec agent runs alongside
  APISIX and inspects every request that passed Caddy before route plugins
  execute — SQLi/XSS/OWASP-coverage WAF decisions at the gateway hop.
- No OpenAppSec server deployment exists in this repository yet; the flag is
  the seam. When the upstream is source-locked and approved, the agent
  attaches to the APISIX pod without changes to Caddy or service charts.

### 3. APISIX gateway (source-locked upstream)

- API routing and authN: bearer-only OIDC (Keycloak discovery URL from the
  render-gated `charts/caddy` OIDC contract ConfigMap) with per-route
  required scopes; admin consoles use the authorization-code flow as OIDC
  relying parties.
- Identity-aware rate limiting (`limit-req`, per consumer + remote address)
  below the coarse Caddy ceiling.
- Schema validation and request normalization before any service hop.
- Coarse-grained edge authorization via the `opa` plugin against the OPA
  deployment reconciled by `charts/opa-policies` (policy
  `blueeconomy/http/allow` plus the platform packs).

### 4. Dapr sidecar mesh (`charts/dapr-components`)

- mTLS between sidecars; per-workstream component scopes hard-restricted to
  the approved app-ids (cvff fiduciary segregation, isr national-security
  segregation) — unchanged by this layer.

### 5. Workstream services

- Service-level authN/authZ (Keycloak RS256 JWKS, default-deny route
  tables), PostgreSQL FORCE RLS per tenant, and the Cilium L3/L4/L7
  policies from `charts/cilium` as the network backstop.

## Failure posture

Every layer fails closed: Caddy render gates refuse missing domains,
upstreams, partner CA or OIDC discovery URL; the OpenAppSec flag cannot be
disabled at render time; OPA denies by default (`default allow := false`);
Dapr scopes and Cilium policies deny anything not explicitly listed.
