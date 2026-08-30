# Authorization-service decision: no Permify chart (license-decided)

Status: DECIDED (W-OPS1, 2026-08-30). Register refs: PRA-105 (Permify
fail-open class), W-OTEL-0 honesty flag ("Permify has NO chart anywhere
in the estate — grep-verified; nothing to attach OTLP to").

## Facts (license decides, not preference)

| Component | License | Evidence |
|---|---|---|
| `permify/permify` (core server) | **AGPL-3.0** (core) / commercial | pkg.go.dev `github.com/Permify/permify/cmd/permify` ("License: AGPL-3.0"); GitHub repo license flag `agpl-3.0` |
| `openfga/openfga` (server, SDKs, official Helm chart) | **Apache-2.0** | github.com/openfga LICENSE; FOSSA report; official `openfga/openfga` Helm chart Apache-2.0 |
| `authzed/spicedb` (alternative) | **Apache-2.0** | github.com/authzed/spicedb LICENSE |

Additional governance fact: Permify has been acquired by FusionAuth
(announcement on the upstream repository); the AGPL core's long-term
maintenance posture is uncertain.

## Decision

1. **No Permify chart is added to this estate.** The platform component
   policy is permissive-licenses-only for source-locked/deployed
   components (every entry in `components/upstream-components.lock.yaml`
   is Apache-2.0/MIT-class; the estate previously rejected AGPL
   Ultralytics on the same grounds). AGPL-3.0's network-copyleft on a
   central authorization service — called over the network by every
   service in the estate — is exactly the contagion surface that policy
   excludes. The license fact alone decides against option (a)
   (adding a Permify chart); no engineering preference was weighed.
2. **Successor recommendation: OpenFGA (Apache-2.0)** when the
   authorization-service wave lands — Zanzibar-class API like Permify,
   official Apache-2.0 Helm chart source-lockable through
   `components/upstream-components.lock.yaml`, PostgreSQL backend
   (aligns with the estate's data tier), native OTel. SpiceDB
   (Apache-2.0) is the documented second choice. Migration cost is
   real: singlewindow services integrate the Permify API/SDK
   (PRA-105 class) and must be re-pointed — that is service-repo work,
   out of scope here.
3. **OTel coverage consequence (honest):** the W-OTEL APISIX/Keycloak/
   Permify native-OTel row has nothing to attach to for the
   authorization service until the successor is charted. This is
   recorded as an accepted gap, not worked around.
4. **Phantom-reference hygiene:** the GitOps layer must not carry
   Permify wiring (routes, network rules, collector config) for a
   component that does not exist in the estate. The validator refuses
   any Permify reference in `charts/` that does not point at this
   document.

## Revisit triggers

- The authorization-service wave selects and charts the successor
  (OpenFGA recommended above); or
- upstream license terms change (re-verify the LICENSE file at pin
  time — policy is facts-at-pin-time, not this snapshot).
