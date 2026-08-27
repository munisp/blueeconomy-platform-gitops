# GitOps controller: Argo CD

This repository is reconciled by **Argo CD** (pinned upstream:
`components/upstream-components.lock.yaml` entry `argo-cd`, kustomize manifest
`manifests/cluster-install` at tag `v3.5.2`, commit-pinned).

## Why Argo CD (and not Flux)

| Criterion | Argo CD | Flux |
|---|---|---|
| Multi-source Applications (chart repo + environment values repo) | Native (`spec.sources[]` + `$values` ref) | Requires `HelmRelease` valuesFrom indirection |
| Per-workstream fan-out from one repo | `ApplicationSet` list generator | No direct equivalent (kustomize templating) |
| Approval-gated hooks (realm import, Temporal namespace bootstrap) | Native sync hooks (`PostSync`) | Kustomize/Helm controller hooks differ |
| Ministry audit/oversight UI for observers (`auditor`, `fmmbe-oversight`) | Built-in RBAC-scoped UI/API | No bundled UI |

Both controllers are compatible with the pinned components; Argo CD was
selected for the reasons above. All GitOps manifests live under
`gitops/argocd/`:

- `project.yaml` — `AppProject blueeconomy-platform`: source-repo allow-list,
  destination allow-list (the five platform namespaces), cluster-resource
  allow-list limited to `Namespace`, orphaned-resource warnings.
- `application-platform-base.yaml` — reconciles `kubernetes/base`
  (namespaces, restricted PSA labels, default-deny NetworkPolicies, CVFF
  cross-workstream ingress denial).
- `applicationset.yaml` — one `Application` per chart:
  `ferry-ticketing` → `blueeconomy-ferries`,
  `port-interoperability` → `blueeconomy-ports`,
  `financial-controls` → `blueeconomy-cvff`,
  `security-operations` → `blueeconomy-security`,
  `temporal` + `keycloak-realms` → platform/security namespaces, and one
  `dapr-components` release per workstream (`workstream.name` parameter)
  rendered into the workstream namespace.

## Fail-closed behaviour under Argo CD

Chart default values deliberately fail `helm template` (approval gates:
image digests, ExternalSecrets store references, per-service required
environment). An Application whose environment values are absent therefore
surfaces the gate message as its sync error instead of deploying anything.
Approved values arrive from the authorised environment repository
(`$values/environments/prod/<chart>.yaml`, multi-source).

## Bootstrap order

1. Install the pinned Argo CD manifests (lockfile `argo-cd` entry).
2. Apply `gitops/argocd/project.yaml`.
3. Apply `gitops/argocd/application-platform-base.yaml` (creates namespaces).
4. Apply `gitops/argocd/applicationset.yaml`.
5. Provision the environment repository with approved per-chart values and
   the Azure Key Vault `ClusterSecretStore` (see
   `docs/azure-government-landing-zone.md`).
