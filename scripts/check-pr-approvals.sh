#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORY_OWNER="${REPOSITORY_OWNER:-munisp}"
WATCH_SECONDS="${WATCH_SECONDS:-0}"
READY_WEBHOOK_URL="${READY_WEBHOOK_URL:-}"

PRS=(
  "blueeconomy:1"
  "blueeconomy-platform-gitops:1"
  "blueeconomy-platform-gitops:2"
  "blueeconomy-platform-gitops:3"
  "blueeconomy-ministry-portal:1"
  "blueeconomy-waterway-safety:1"
  "blueeconomy-credential-verification:1"
  "blueeconomy-port-interoperability:1"
  "blueeconomy-port-interoperability:2"
  "blueeconomy-maritime-intelligence:1"
  "blueeconomy-financial-controls:1"
  "blueeconomy-data-platform:1"
  "blueeconomy-administration-service:1"
  "blueeconomy-security-operations:1"
  "blueeconomy-maritime-evidence:1"
  "blueeconomy-contracts:1"
  "blueeconomy-developer-platform:1"
  "blueeconomy-traceability:1"
)

require_command() {
  command -v "$1" >/dev/null 2>&1 || { printf 'ERROR: missing command: %s\n' "$1" >&2; exit 1; }
}

check_once() {
  local ready=0 blocked=0 errors=0
  local report='['
  for item in "${PRS[@]}"; do
    local repo="${item%%:*}"
    local number="${item##*:}"
    local api_repo="${REPOSITORY_OWNER}/${repo}"
    local title state mergeable mergeable_state approvals url

    title="$(gh api "repos/${api_repo}/pulls/${number}" --jq '.title' 2>/dev/null)" || { errors=$((errors+1)); continue; }
    state="$(gh api "repos/${api_repo}/pulls/${number}" --jq '.state' 2>/dev/null || true)"
    mergeable="$(gh api "repos/${api_repo}/pulls/${number}" --jq '.mergeable' 2>/dev/null || true)"
    mergeable_state="$(gh api "repos/${api_repo}/pulls/${number}" --jq '.mergeable_state' 2>/dev/null || true)"
    approvals="$(gh api "repos/${api_repo}/pulls/${number}/reviews?per_page=100" --jq '[.[] | select(.state == "APPROVED") | .user.login] | unique | length' 2>/dev/null || true)"
    url="https://github.com/${api_repo}/pull/${number}"

    [[ "$approvals" =~ ^[0-9]+$ ]] || approvals=0
    if [[ "$state" == "open" && "$approvals" -ge 2 && "$mergeable" == "true" && "$mergeable_state" == "clean" ]]; then
      ready=$((ready+1))
      status='READY_FOR_REVIEWED_MERGE'
    else
      blocked=$((blocked+1))
      status='BLOCKED'
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "#$number" "$approvals" "$mergeable" "$mergeable_state" "$status" "$url"
  done

  printf 'TOTAL_READY=%s TOTAL_BLOCKED=%s ERRORS=%s\n' "$ready" "$blocked" "$errors"
  if [[ "$ready" -eq "${#PRS[@]}" && "$errors" -eq 0 ]]; then
    printf '%s\n' 'ALL_PR_APPROVALS_READY=true'
    if [[ -n "$READY_WEBHOOK_URL" ]]; then
      curl --fail --silent --show-error -X POST -H 'Content-Type: application/json' \
        --data '{"event":"blueeconomy_pr_approval_gate_ready","count":18}' \
        "$READY_WEBHOOK_URL" >/dev/null
    fi
    return 0
  fi
  printf '%s\n' 'ALL_PR_APPROVALS_READY=false'
  return 2
}

require_command gh
if [[ -n "$READY_WEBHOOK_URL" ]]; then require_command curl; fi

if [[ "$WATCH_SECONDS" -gt 0 ]]; then
  while true; do
    date -u +%Y-%m-%dT%H:%M:%SZ
    check_once || true
    sleep "$WATCH_SECONDS"
  done
else
  check_once
fi
