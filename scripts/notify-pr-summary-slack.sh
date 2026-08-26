#!/usr/bin/env bash
set -Eeuo pipefail

message_file="${1:-}"
[[ -n "$message_file" && -f "$message_file" ]] || { printf 'ERROR: usage: %s MESSAGE_FILE\n' "$0" >&2; exit 64; }
: "${SLACK_WEBHOOK_URL:?SLACK_WEBHOOK_URL is required}"
command -v curl >/dev/null 2>&1 || { printf 'ERROR: curl is required\n' >&2; exit 127; }
command -v jq >/dev/null 2>&1 || { printf 'ERROR: jq is required\n' >&2; exit 127; }

payload="$(jq -n --rawfile text "$message_file" '{text: $text}')"
curl --fail --silent --show-error --max-time 20 \
  -H 'Content-Type: application/json' \
  --data "$payload" \
  "$SLACK_WEBHOOK_URL" >/dev/null
printf '%s\n' 'Slack notification sent.'
