# financial-controls chart

Deploys the CVFF fiduciary workstream into the `blueeconomy-cvff` namespace.
Every credential arrives through ExternalSecrets; every image reference is a
digest; every component fails closed without its required environment.

## Deployed components (services)

| Component | Binary | Port | Purpose |
| --- | --- | --- | --- |
| `intent-api` | `intent-api` | 8080 | `/v1/financial-intents*` — create/approve/void/resolve. Keycloak JWT + realm-role + PBAC gate on every money route; maker/checker/officer identity is the verified token subject. Requires Keycloak realm coordinates, the baked-in PBAC pack (`/etc/blueeconomy/policies`) and TigerBeetle coordinates (officer VOID resolution compensates reservations against the real ledger). |
| `cvff-api` | `cvff-api` | 8081 | `/v1/cvff/applications*` — the ONLY server of the beneficiary-portal CVFF contract. Requires Keycloak coordinates, AV scanner URL, object-storage backend coordinates, Temporal and the baked-in PBAC pack. |
| `declaration-scorer` | `declaration-scorer` | 8082 | `POST /v1/risk-scores` — the provider behind port-interoperability's `DECLARATIONS_SCORER_URL`. Deterministic rules-based scoring (no ML) from the versioned rules baked into the image (`/etc/declaration-scorer/rules.json`). |
| `cvff-worker` | `cvff-worker` | — | Temporal worker for the disbursement rail; also runs the FX pending-confirmation expiry sweep (`FX_PENDING_CONFIRMATION_TTL`, required). |
| `outbox-publisher` | `outbox-publisher` | — | Publishes the CVFF outbox to Kafka. |

## Operator-run binaries (NOT deployed by this chart — honest boundary)

The remaining binaries in `blueeconomy-financial-controls` are deliberate
operator/job tools and are **not** given Deployments here:

- `financial-orchestrator` — per-intent reserve/post/void operations
  (`--operation`, `--intent-id`). Run by an operator (or a future approved
  automation) against DATABASE_URL + TigerBeetle; never a long-lived service.
- `financial-reconcile` — statement reconciliation batch job
  (`STATEMENT_PATH`/`REPORT_PATH`).
- `tigerbeetle-ledger` — direct ledger account/transfer administration tool.
- `tigerbeetle-verifier` — ledger evidence/verification tool.
- `mojaloop-adapter` — the receive-only Mojaloop callback rail. It is
  deployed through the **`mojaloop-overlay` chart** (Hub profile, JWS keys,
  TLS), not this chart. Its `MOJALOOP_RESERVED_TIMEOUT_SECONDS` (required)
  drives the RESERVED-timeout sweep.

## Notes

- The Dapr app-ids `cvff-api` and `declaration-scorer` must be present in the
  environment's `dapr-components` values (`workstream cvff` appIds list)
  alongside `intent-api`, `cvff-worker` and `cvff-outbox-publisher`.
