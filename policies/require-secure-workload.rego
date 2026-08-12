package blueeconomy.kubernetes.security

# Deny workload pods that do not explicitly prohibit privilege escalation.
deny[msg] {
  input.kind.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  not container.securityContext.allowPrivilegeEscalation == false
  msg := sprintf("container %q must set securityContext.allowPrivilegeEscalation=false", [container.name])
}

# Deny workload pods that do not run as non-root.
deny[msg] {
  input.kind.kind == "Deployment"
  not input.spec.template.spec.securityContext.runAsNonRoot == true
  msg := "pod template must set securityContext.runAsNonRoot=true"
}

# Deny mutable container tags, which do not provide immutable deployment provenance.
deny[msg] {
  input.kind.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  endswith(container.image, ":latest")
  msg := sprintf("container %q uses forbidden mutable :latest image tag", [container.name])
}
