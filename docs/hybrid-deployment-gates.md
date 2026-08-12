# Hybrid Deployment Gates

The platform will run across Ministry-approved cloud and on-premises environments. The exact distribution, clusters, network paths, certificate authority, image registry, secret management, backup target, observability path and disaster-recovery location are not yet available in this repository. The base manifests therefore enforce only environment-independent isolation and policy requirements.

Before a real deployment, the Design Authority must approve environment overlays that identify the actual target and its owners. Each overlay must be reviewed for namespace separation, service account/workload identity, network egress, image registry/digest, storage class, backup/recovery, resource limits, ingress/TLS, audit logging and data classification. No default endpoint, credential or target cluster is assumed.
