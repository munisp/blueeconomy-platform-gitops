#!/usr/bin/env bash
# Static validation of the rendered ApisixRoute inventory (WP-E):
#   1. every plugin reference resolves against the known APISIX plugin set
#   2. every upstream backend service resolves against the declared
#      services list (routeValidation.knownServices in the values file)
#   3. no duplicate route URIs (host + path pairs)
#   4. TLS posture: routes marked tls.required=true must render the
#      edge TLS marker (proxy-rewrite X-Forwarded-Proto: https) and must
#      never target a wildcard host.
# Exits non-zero on any violation with a stable reason code per finding.
# Render-only gate: no cluster is contacted.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: validate-apisix-routes.sh [--chart DIR] [--values FILE] [--rendered FILE]

Renders the apisix-routes chart with the given values file (default:
charts/apisix-routes + ci/render-values/apisix-routes.yaml) and statically
validates every rendered ApisixRoute. With --rendered, validates a
pre-rendered manifest instead of invoking helm.

Reason codes (one per line on stdout, also in the report):
  APISIX_RENDER_FAILED        helm template failed
  APISIX_PLUGIN_UNKNOWN       plugin reference does not resolve
  APISIX_UPSTREAM_UNRESOLVED  backend service not in the declared services list
  APISIX_DUPLICATE_ROUTE_URI  duplicate host+path across routes
  APISIX_TLS_REQUIRED         tls.required route missing the edge TLS marker

Exit status: 0 = pass, 1 = violations found, 2 = usage/preflight error.
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chart="$repo_root/charts/apisix-routes"
values="$repo_root/ci/render-values/apisix-routes.yaml"
rendered=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --chart) chart="${2:-}"; shift ;;
    --values) values="${2:-}"; shift ;;
    --rendered) rendered="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

command -v python3 >/dev/null 2>&1 || { echo "ERROR: required dependency 'python3' not found on PATH" >&2; exit 2; }
python3 -c 'import yaml' 2>/dev/null || { echo "ERROR: python3 module 'yaml' (PyYAML) is required" >&2; exit 2; }

if [ -z "$rendered" ]; then
  command -v helm >/dev/null 2>&1 || { echo "ERROR: required dependency 'helm' not found on PATH" >&2; exit 2; }
  [ -d "$chart" ] || { echo "ERROR: chart directory not found: $chart" >&2; exit 2; }
  rendered="$(mktemp)"
  trap 'rm -f "$rendered"' EXIT
  if ! helm template validate "$chart" --kube-version "${HELM_KUBE_VERSION:-1.28.0}" -f "$values" > "$rendered"; then
    echo "APISIX_RENDER_FAILED helm template failed for $chart with $values"
    exit 1
  fi
fi
[ -f "$values" ] || { echo "ERROR: values file not found: $values" >&2; exit 2; }

python3 - "$rendered" "$values" <<'PYEOF'
import sys
import yaml

rendered_path, values_path = sys.argv[1], sys.argv[2]

with open(rendered_path, encoding="utf-8") as fh:
    docs = [d for d in yaml.safe_load_all(fh) if isinstance(d, dict)]
with open(values_path, encoding="utf-8") as fh:
    values = yaml.safe_load(fh) or {}

# Known APISIX plugin set the edge is approved to use (plugin references
# must resolve against this list; unknown plugins fail closed).
KNOWN_PLUGINS = {
    "openid-connect", "opa", "limit-req", "limit-count", "limit-conn",
    "proxy-rewrite", "opentelemetry", "prometheus", "cors",
    "response-rewrite", "redirect", "gzip", "real-ip", "ua-restriction",
    "referer-restriction", "uri-blocker", "request-validation",
    "proxy-cache", "fault-injection", "serverless-pre-function",
    "ip-restriction", "key-auth", "jwt-auth", "basic-auth", "hmac-auth",
    "wolf-rbac", "authz-keycloak", "authz-casbin", "forward-auth",
}

# Declared services list: "namespace/name" entries the route upstreams are
# allowed to target (approved service registry for the edge).
known = (values.get("routeValidation") or {}).get("knownServices") or []
known_services = set(known)
violations = []

# Per-route TLS markings and declared upstreams from the values source
# (the values entry carries the backend namespace; the rendered CR targets
# the service by name via resolveGranularity=service).
tls_required = {}
values_upstreams = {}
for r in values.get("routes") or []:
    name = (r or {}).get("name")
    if not name:
        continue
    tls_required[name] = bool(((r or {}).get("tls") or {}).get("required", True))
    svc = ((r or {}).get("service") or {})
    if svc.get("namespace") and svc.get("name"):
        values_upstreams[name] = f"{svc['namespace']}/{svc['name']}"

# 2a. declared upstreams must resolve against the known services list.
if known_services:
    for route_name, nsname in values_upstreams.items():
        if nsname not in known_services:
            violations.append(
                f"APISIX_UPSTREAM_UNRESOLVED route={route_name} service={nsname}")
else:
    violations.append(
        "APISIX_UPSTREAM_UNRESOLVED routeValidation.knownServices is empty "
        "(declare the approved edge-reachable services)")

routes = [d for d in docs if d.get("kind") == "ApisixRoute"]
if not routes:
    print("APISIX_RENDER_FAILED no ApisixRoute documents in rendered output")
    sys.exit(1)

seen_uris = {}

for route in routes:
    meta = route.get("metadata") or {}
    rname = meta.get("name", "<unknown>")
    for http in ((route.get("spec") or {}).get("http") or []):
        route_name = http.get("name", rname)
        match = http.get("match") or {}
        hosts = match.get("hosts") or []
        paths = match.get("paths") or []

        # 1. plugin references resolve
        for plugin in http.get("plugins") or []:
            pname = (plugin or {}).get("name")
            if pname not in KNOWN_PLUGINS:
                violations.append(
                    f"APISIX_PLUGIN_UNKNOWN route={route_name} plugin={pname}")

        # 2. upstream service names resolve against the declared list
        ns = meta.get("namespace", "")
        for backend in http.get("backends") or []:
            svc = (backend or {}).get("serviceName")
            # The backend namespace is the route values entry's service
            # namespace; the CR targets it via resolveGranularity=service.
            candidates = [f"{svc}", f"{ns}/{svc}"]
            if known_services and not any(
                    any(k.endswith(f"/{svc}") or k == svc for k in known_services)
                    for _ in [0]):
                violations.append(
                    f"APISIX_UPSTREAM_UNRESOLVED route={route_name} service={svc}")

        # 3. no duplicate route URIs (host + path)
        for host in hosts:
            if host == "*" or "*" in str(host):
                violations.append(
                    f"APISIX_TLS_REQUIRED route={route_name} wildcard host {host!r} refused")
            for path in paths:
                key = (host, path)
                if key in seen_uris:
                    violations.append(
                        f"APISIX_DUPLICATE_ROUTE_URI {host}{path} "
                        f"routes={seen_uris[key]},{route_name}")
                else:
                    seen_uris[key] = route_name

        # 4. TLS posture where marked
        if tls_required.get(route_name, True):
            marker = False
            for plugin in http.get("plugins") or []:
                if (plugin or {}).get("name") == "proxy-rewrite":
                    headers = (((plugin or {}).get("config") or {})
                               .get("headers") or {}).get("set") or {}
                    if headers.get("X-Forwarded-Proto") == "https":
                        marker = True
            if not marker:
                violations.append(
                    f"APISIX_TLS_REQUIRED route={route_name} missing "
                    f"proxy-rewrite X-Forwarded-Proto: https marker")

if violations:
    for v in violations:
        print(v)
    print(f"RESULT=FAIL violations={len(violations)}")
    sys.exit(1)
print(f"RESULT=PASS routes={len(routes)} uris={len(seen_uris)} "
      f"knownServices={len(known_services)}")
PYEOF
