# Blue Economy Platform GitOps

This repository contains non-secret Kubernetes policy, source locks and deployment-source declarations for the hybrid Blue Economy Platform. It does not contain a kubeconfig, cloud credentials, partner endpoints, certificates, TLS private keys, runtime secrets, fabricated environment values or production data.

The current base applies namespace boundaries and policy source. The `charts/` directory now versions the Ministry-owned TigerBeetle StatefulSet pattern, the Mojaloop release-control overlay, the Sedona Spark job pattern and a disabled-by-default umbrella chart. Each service chart fails rendering when required approved environment values are absent. No example values are supplied because the Ministry environment registry, immutable image digests, infrastructure identifiers and regulated authorities have not been provided.

A source lock, successful lint or rendered manifest is **not** evidence of deployment. A deployment is verified only when an authorized hybrid target, reviewed environment values, change approval, target-side health and security evidence, recovery testing and the applicable business acceptance record are all retained. See `docs/core-services-deployment-guide.md` and `policies/core-services-production-guardrails.md`.

Run the local source validation with:

```bash
bash scripts/validate-manifests.sh
```
