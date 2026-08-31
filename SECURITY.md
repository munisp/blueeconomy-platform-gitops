# Security Posture — blueeconomy-platform-gitops

Phase 11 security audit (branch `phase11/security`).

## Controls verified
- **Secrets**: working-tree scan clean; secrets only via ExternalSecrets/ESO (storeRef required by render gates; no inline secrets).
- **Pod security**: mission-service charts (financial-controls, tax-stamps, insurance, port-interoperability, geo-service, maritime-intelligence, cv-service, agency-sandbox) all default to runAsNonRoot, readOnlyRootFilesystem, drop ALL caps, seccomp RuntimeDefault, automountServiceAccountToken=false.
- **NetworkPolicies**: every mission chart ships an enabled default-deny NetworkPolicy; shared namespaces (platform/security/ports/ferries/cvff/seafarer/fisheries/isr) ship Namespace + default-deny NetworkPolicy; cvff fiduciary and isr national-security cross-workstream ingress denials verified by gates.
- **Sandbox segregation**: agency-sandbox chart refuses profile=prod (render-gate verified this phase).

## Fixes this phase
- **HIGH (fail-closed regression)**: restored `charts/dapr-components/templates/000-validation.yaml` (lost from main) — without it the chart rendered without `workstream.name`, and the cvff/isr Dapr scope-segregation render gates were unenforced. `scripts/validate-manifests.sh` is exit 0 again (was failing).
- `validate-manifests.sh` now invokes `validate-apisix-routes.sh` via `bash` (exec bit is not portable across FUSE/CI filesystems).

## Residuals
- Many non-mission charts (third-party wrappers) still lack explicit pod securityContexts in templates; recommend a follow-up sweep. Policy enforcement (PSA restricted) exists for sensitive namespaces.
