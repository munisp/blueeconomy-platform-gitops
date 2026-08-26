#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${PR_MONITOR_STATE_FILE:-/var/lib/blueeconomy/all-prs-ready.sent}"
NOTIFICATION_FILE="${PR_MONITOR_MESSAGE_FILE:-/var/lib/blueeconomy/pr-ready-message.txt}"
POLL_SECONDS="${WATCH_SECONDS:-300}"

[[ "$POLL_SECONDS" =~ ^[1-9][0-9]*$ ]] || { printf 'ERROR: WATCH_SECONDS must be a positive integer\n' >&2; exit 64; }
: "${SLACK_WEBHOOK_URL:?SLACK_WEBHOOK_URL is required}"
mkdir -p "$(dirname "$STATE_FILE")" "$(dirname "$NOTIFICATION_FILE")"

while true; do
  output="$(WATCH_SECONDS=0 "$ROOT_DIR/scripts/check-pr-approvals.sh" 2>&1)" || status=$?; status=${status:-0}
  printf '%s\n' "$output"
  if [[ "$status" -eq 0 && ! -e "$STATE_FILE" ]]; then
    printf '%s\n' "$output" > "$NOTIFICATION_FILE"
    if "$ROOT_DIR/scripts/notify-pr-summary-slack.sh" "$NOTIFICATION_FILE"; then
      umask 077
      : > "$STATE_FILE"
    fi
  fi
  unset status
  sleep "$POLL_SECONDS"
done
