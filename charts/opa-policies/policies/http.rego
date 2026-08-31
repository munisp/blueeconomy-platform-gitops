# APISIX edge hook policy, promoted from the umbrella seed
# (blueeconomy/deploy/security/opa/blueeconomy_http.rego).
# APISIX passes validated OIDC claims and normalized request/resource
# attributes; this is the coarse-grained edge decision. Deny by default.
package blueeconomy.http

import rego.v1

default allow := false

default reason := "deny-by-default"

allow if {
	valid_subject
	valid_tenant
	valid_audience
	allowed_route
	role_allows_action
	resource_tenant_matches
	no_sensitive_header_override
}

valid_subject if input.subject.sub != ""
valid_tenant if startswith(input.subject.tenant_id, "tenant-")
valid_audience if input.subject.aud == "blueeconomy-api"
no_sensitive_header_override if not input.request.headers["x-tenant-id"]
resource_tenant_matches if input.resource.tenant_id == input.subject.tenant_id

allowed_route if input.request.method == "POST"; startswith(input.request.path, "/v1/port/")
allowed_route if input.request.method == "GET"; startswith(input.request.path, "/v1/port/")
allowed_route if input.request.method == "POST"; startswith(input.request.path, "/v1/feed-sources/")
allowed_route if input.request.method == "GET"; startswith(input.request.path, "/v1/feed-sources/")
allowed_route if input.request.method == "POST"; startswith(input.request.path, "/v1/nsw/")

role_allows_action if "platform-admin" in input.subject.roles
role_allows_action if "s1-operator" in input.subject.roles; startswith(input.request.path, "/v1/port/")
role_allows_action if "s2-analyst" in input.subject.roles; startswith(input.request.path, "/v1/feed-sources/")

reason := "allowed" if allow
reason := "tenant mismatch" if valid_subject; valid_tenant; input.resource.tenant_id != input.subject.tenant_id
reason := "caller tenant header prohibited" if input.request.headers["x-tenant-id"]
