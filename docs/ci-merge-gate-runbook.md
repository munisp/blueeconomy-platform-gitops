# GitOps CI/CD Merge-Gate Runbook

## Required GitHub status check

The protected `main` branch must require the exact check context:

```text
GitOps Policy Gates / Validate manifests
```

This is the job display name from `.github/workflows/gitops-policy-gates.yml`. Branch protection must require the check before merge, require the branch to be up to date before testing, require a pull request and designated code-owner review, resolve conversations, restrict direct pushes, and prevent bypass except for the explicitly approved break-glass administrators. The branch rule is a GitHub repository-administration responsibility; this file does not claim that it has been configured in the remote repository.

## Pull-request execution path

1. A pull request touching `charts/**`, `kubernetes/**`, `components/**`, `policies/**`, `scripts/**` or the workflow itself triggers the job.
2. The workflow checks out the immutable `actions/checkout` reference with `contents: read`, concurrency cancellation and a ten-minute timeout.
3. It confirms the required local tools, runs whitespace checks and scans changed GitOps sources for PEM/private-key/JWT-like material.
4. It runs `HELM_KUBE_VERSION=1.28.0 ./scripts/validate-manifests.sh`. This validates namespace/network-policy sources, upstream lock entries and SHA-256 counts, chart sources, fail-closed defaults, the Core Services render/lint and Mojaloop Keycloak/mTLS/APISIX/partner-route guards.
5. It checks that no other workflow contains `kubectl apply`, Helm install/upgrade/rollback, Argo sync or Flux reconcile commands. This job therefore cannot deploy or mutate a cluster.
6. The check must be green before GitHub permits merge. A missing, cancelled, failed or stale check is a merge block.

## Required repository settings

| Setting | Required value |
|---|---|
| Branch | `main` |
| Required check | `GitOps Policy Gates / Validate manifests` |
| Strict status | Require branches to be up to date before merging. |
| Reviews | Pull request required; designated code-owner approval required; stale approvals dismissed on new commits. |
| Conversation state | Require all conversations resolved. |
| Direct push | Restrict or disable direct pushes; use reviewed pull requests. |
| Bypass | No routine bypass; break-glass use requires recorded incident/change approval. |
| Deployment | Not part of this merge gate. Deployment/reconciliation occurs only in a separately authorized promotion pipeline after all evidence and approvals exist. |

## Relationship to candidate-binding checks

The GitOps status check validates repository manifests and chart policy. The `blueeconomy` repository’s `Target Verification Safety` check validates offline closeout/candidate structure, dry-run enumeration and local GitOps identity reconciliation when those files are supplied. Neither check establishes Ministry signature, PKI, KMS/HSM, live reconciler identity or target acceptance.

For a protected promotion, the authorized promotion pipeline must require both repository checks plus the Ministry-controlled evidence adapter and final audit verifier. The latter must supply the candidate/export binding and approved attestation; the local GitHub jobs cannot manufacture or query that evidence.

## Local reproduction

```bash
cd /path/to/blueeconomy-platform-gitops
git diff --check
HELM_KUBE_VERSION=1.28.0 ./scripts/validate-manifests.sh
```

The CI job’s check is authoritative only for the commit tested by GitHub. A rendered or locally validated chart is not evidence that it has been applied to a Ministry cluster.
