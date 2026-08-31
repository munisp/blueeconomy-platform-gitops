# Admin tenant-scoping pack, mirroring the administration-service default-
# deny route policy. Edge-coarse: cross-tenant administration is denied;
# caller-supplied tenant headers are prohibited (the token is the only
# tenancy source).
package blueeconomy.admin

import rego.v1

default allow := false

default reason := "deny-by-default"

allow if {
	valid_subject
	tenant_scoped
	no_sensitive_header_override
	role_allows_admin
}

valid_subject if input.subject.sub != ""

tenant_scoped if startswith(input.subject.tenant_id, "tenant-")
tenant_scoped if input.subject.tenant_id == "tenant-platform"

no_sensitive_header_override if not input.request.headers["x-tenant-id"]

role_allows_admin if "platform-admin" in input.subject.roles
role_allows_admin if {
	"tenant-admin" in input.subject.roles
	input.resource.tenant_id == input.subject.tenant_id
	input.resource.tenant_id != "tenant-platform"
}

reason := "allowed" if allow
reason := "cross-tenant administration denied" if {
	valid_subject
	"tenant-admin" in input.subject.roles
	input.resource.tenant_id != input.subject.tenant_id
}
reason := "caller tenant header prohibited" if input.request.headers["x-tenant-id"]
