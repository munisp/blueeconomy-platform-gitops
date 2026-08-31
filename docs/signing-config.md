# Signing configuration: envelope vs provenance env-var conventions (gap #40)

Every event-producing service signs the canonical event envelope
(RFC 8785 JCS canonicalization + JWS EdDSA). Two environment-variable
conventions exist in the estate; this document is the authoritative
statement of both and of the deprecation path between them.

## The two conventions

| Convention | Env vars | Status |
|---|---|---|
| `envelope` | `ENVELOPE_SIGNING_PRIVATE_KEY`, `ENVELOPE_SIGNING_PRIVATE_KEY_EPOCH` | **Target.** All new services use this. The epoch identifies the active key generation, so rotation is a first-class operation: consumers accept the current and previous epoch during a rotation window. |
| `provenance` | `PROVENANCE_SIGNING_KEY` | **Legacy / deprecating.** Carried by the first-generation producers. No epoch: rotation requires coordinated redeploy, which is why it is being replaced. |

## The rule

1. **Exactly one convention per service release.** A deployment must never
   mix the two. `charts/geo-service` enforces this fail-closed at render
   time (`signing.convention: envelope | provenance`; the gate requires the
   selected convention's keys in `secretEnv` and refuses the other
   convention's keys). New services MUST use `envelope`.
2. **Keys arrive only via ExternalSecrets.** Signing private keys are never
   inline values; they sync from the landing zone's secret store (any
   ESO-supported backend, per `docs/cloud-agnosticism.md`) into the
   release's env Secret.
3. **Consumers verify, not sign.** Verification uses the producer public-key
   directory (`charts/opa-policies` `keyDirectory`) keyed by `kid`; the
   kid↔epoch mapping is environment configuration, not chart defaults.

## Deprecation path (provenance → envelope)

1. Service exposes both mappings in chart values (already true:
   `charts/geo-service` `signing.envelope.*` / `signing.provenance.*`).
2. Environment values switch `signing.convention: provenance` → `envelope`
   and add `ENVELOPE_SIGNING_PRIVATE_KEY` + `ENVELOPE_SIGNING_PRIVATE_KEY_EPOCH`
   remote refs to the ExternalSecret. The render gate refuses the
   transition state (both conventions' keys present), so the cut-over is
   atomic per release.
3. Consumers accept envelopes signed under either convention during the
   migration window (the signature envelope format is identical; only the
   env-var sourcing differs), so no consumer change is required.
4. Once every producer in an environment renders with
   `signing.convention: envelope`, the `provenance` branch is retired from
   the values schema in a later chart version. The convention itself is
   never silently removed — retirement lands in the chart CHANGELOG and
   this document.
