# Azure Government / AKS landing-zone assumptions

The shared-platform layer targets an **AKS cluster in an Azure Government
(USGov) region**. This file records the assumptions baked into chart values
and comments; environment-specific values are supplied by the authorised
environment repository, never committed here.

## Sovereign endpoints (USGov)

| Service | Azure Government endpoint | Commercial (do not use in Gov) |
|---|---|---|
| Microsoft Entra ID (AAD) authority | `https://login.microsoftonline.us` | `login.microsoftonline.com` |
| Key Vault DNS suffix | `vault.usgovcloudapi.net` | `vault.azure.net` |
| Resource Manager | `https://management.usgovcloudapi.net` | `management.azure.com` |
| Container registry | `<registry>.azurecr.us` | `<registry>.azurecr.io` |

## Where these apply

- **Dapr `secretstores.azure.keyvault` components**
  (`charts/dapr-components`): `azureEnvironment: AzureUSGovernmentCloud`
  (default in values) makes the Dapr Azure SDK select the USGov authority and
  vault endpoints. Override to `AzurePublicCloud` only on commercial
  development clusters.
- **ExternalSecrets `ClusterSecretStore`** (referenced by every chart via
  `externalSecrets.storeRef.name`, fail-closed): the environment repository
  defines an Azure Key Vault provider store pointed at the USGov vault with
  AKS workload identity (no client secrets).
- **Image references**: all service images are digest-pinned and hosted in a
  USGov ACR (`*.azurecr.us`) per the environment values.
- **Keycloak realms** (`charts/keycloak-realms`): cluster-local service URLs;
  no sovereign endpoint dependency. Token policy is enforced at render time
  (access token lifespan ≤ 300 s).

## Landing-zone prerequisites (not provisioned by this repository)

- AKS cluster with workload identity enabled, restricted Pod Security
  Standards enforcement, and a CNI enforcing NetworkPolicy.
- External Secrets Operator, Dapr (pinned in
  `components/upstream-components.lock.yaml`), Strimzi Kafka operator,
  CloudNativePG, Prometheus and OpenTelemetry Collector installed per their
  lockfile pins.
- Azure Key Vault (USGov) containing every secret referenced by the
  ExternalSecrets resources; access via workload identity managed by the
  identity team.
- Argo CD installed from the pinned lockfile entry and bound to this
  repository (see `docs/gitops-controller-argocd.md`).
