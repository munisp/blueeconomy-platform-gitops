# Cloud-agnosticism and sovereign-deployability contract

The Blue Economy Platform is **cloud-agnostic and sovereign-deployable**.
It is not anchored to any cloud provider: any conformant Kubernetes
(>= 1.29) is a valid target — on-prem/self-hosted clusters, sovereign
clouds, or commercial clouds. Azure Government remains a fully-supported
landing-zone **option** (`docs/azure-government-landing-zone.md`), never
the assumed target and never a hard requirement.

This document is the platform's provider-neutrality contract. It records,
component by component, which capabilities are pluggable, which provider
options are render-gated today, and the rule governing new couplings.

## The rule

1. **No hard provider dependencies.** A chart, service or runbook must
   never require a specific cloud provider's API, endpoint, SDK or
   managed service to render or run.
2. **New provider couplings are render-gated options only.** Any new
   provider-specific integration is added exclusively as a new member of a
   provider enum (or an equivalent backend selector) whose required values
   fail closed at template time (`required`/`fail` in the chart's
   `000-validation.yaml`). A coupling that cannot be render-gated does not
   merge.
3. **Provider-neutral defaults.** Example values and CI fixtures default
   to provider-neutral options (e.g. `rfc2136` DNS, `s3-compatible`
   storage, the `kubernetes` secret store); provider-specific fixtures
   prove each supported option renders, and negative gates prove unknown
   providers and missing per-provider values are refused.
4. **No option is removed.** Demoting a provider from requirement to
   option must never delete support for it.

## Component-by-component matrix

| Capability | Abstraction | Render-gated options | Where enforced |
|---|---|---|---|
| Compute | Any conformant Kubernetes (>= 1.29): on-prem/self-hosted, sovereign cloud, commercial cloud | n/a — no provider API is consumed | whole repository; charts declare `kubeVersion: ">=1.28.0-0"` and are render-tested with `helm template --kube-version` |
| Object storage (services) | Backend selector per service | `s3` (any S3-compatible endpoint, incl. MinIO/Ceph/GCS S3-interop), `adls` (Azure Data Lake Gen2), `local-gated` (dev-only, explicitly gated) | `blueeconomy-financial-controls` `internal/cvffapi/storage.go` (backends `s3`/`adls`/`local-gated`, `BLUEECONOMY_S3_*` env contract); `blueeconomy-data-platform` `src/blueeconomy_data_platform/storage.py` (`adls`/`s3`/`local-gated`, endpoint/region/credential-chain env) |
| Secret store (Dapr + ExternalSecrets) | Dapr `secretstores.*` components + ESO `ClusterSecretStore` reference | `kubernetes`, `azureKeyVault`, `hashicorpVault` (server + token secret ref, render-gated), `external` (any operator-managed ESO ClusterSecretStore; store name render-gated) | `charts/dapr-components` (`secretStores.*`, `externalSecrets.storeRef`) |
| KMS / key custody | Via the secret-store abstraction above — keys live in the landing zone's chosen backend; nothing provider-specific in-cluster | any ESO-supported KMS-backed store | `charts/dapr-components`, per-chart `externalSecrets.storeRef` gates |
| DNS / ACME (edge TLS) | `tls.acme.dnsProvider.name` enum on the Caddy edge | `rfc2136` (RFC 2136 dynamic DNS — provider-neutral default; BIND/PowerDNS/CoreDNS/any standards-compliant server; nameserver + TSIG secret ref render-gated), `azuredns`, `route53`, `cloudflare`, `googleclouddns`, `digitalocean` (each with its credentials secret ref render-gated), `internal-ca` (no ACME; cert-manager issuer name render-gated), `manual` (operator-supplied TLS secret name render-gated) | `charts/caddy` (`templates/000-validation.yaml`); fixtures `ci/render-values/caddy*.yaml` |
| Backup storage (Velero + WAL-G) | `storage.provider` selector | `s3-compatible` (generic endpoint + region, both render-gated) or `azure` (Azure Blob/ADLS; storage account + resource group render-gated) | `charts/backup-dr` (`templates/000-validation.yaml`, `walg.yaml`, `velero.yaml`); fixtures `ci/render-values/backup-dr*.yaml` |
| Database | PostgreSQL 15+ anywhere (CloudNativePG operator, pinned in `components/upstream-components.lock.yaml`) | n/a — runs on any Kubernetes storage class | `components/upstream-components.lock.yaml`, service charts' connection-string secret refs |
| Geo hot-path store | PostgreSQL 15 + PostGIS via render-gated image enum | `cloudnative-pg` (operator Cluster CR, ghcr.io/cloudnative-pg/postgis operand) or `postgis-image` (plain StatefulSet, postgis/postgis:15-3.5) — both digest-pinned, both storage-class agnostic | `charts/postgis` (`image.variant` in `templates/000-validation.yaml`); fixtures `ci/render-values/postgis*.yaml` |
| Queue / event stream | Kafka anywhere (Strimzi operator, pinned); Dapr `pubsub.kafka` with documented `pubsub.fluvio` variant | brokers/auth via render-gated values, SASL credentials via secret refs | `charts/dapr-components` (`pubsub.*`) |
| Workflow | Temporal anywhere (self-hosted server chart, digest-pinned) | n/a — runs on any Kubernetes | `charts/temporal` |
| Container registry | Any OCI registry; images digest-pinned only | registry host comes from environment values | every chart's `image.repository`/`image.digest` gates |

## How to add a provider option

1. Add the new provider as a member of the relevant enum/selector in the
   chart's `values.yaml`, with a comment block listing its required
   settings. Do not change the default.
2. Extend the chart's `templates/000-validation.yaml` with a fail-closed
   branch: every value the new provider requires is `required`, with a
   message naming the provider and the missing setting.
3. Extend the emitting template(s) with the provider's branch; keep every
   existing provider's branch byte-for-byte intact.
4. Add a CI fixture `ci/render-values/<chart>-<provider>.yaml` proving the
   new provider renders, and a negative gate in
   `scripts/validate-manifests.sh` proving it refuses to render with its
   required values missing.
5. Add the provider to the matrix above and to any per-chart comments
   enumerating the enum.

A proposal that instead introduces a hard dependency on a provider's
managed service is rejected at review, per the rule above.
