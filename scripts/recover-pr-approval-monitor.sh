#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="${SERVICE_NAME:-blueeconomy-pr-approval-monitor.service}"
FAILURE_FILE="${RECOVERY_FAILURE_FILE:-/var/lib/blueeconomy/monitor-failure-count}"
THRESHOLD="${RECOVERY_FAILURE_THRESHOLD:-3}"
MAX_RESTARTS="${RECOVERY_MAX_RESTARTS_PER_WINDOW:-1}"
WINDOW_SECONDS="${RECOVERY_WINDOW_SECONDS:-900}"
STATE_FILE="${RECOVERY_RESTART_STATE_FILE:-/var/lib/blueeconomy/monitor-restart-state}"
log() { logger -t blueeconomy-pr-monitor-recovery -- "$*" 2>/dev/null || true; printf '%s\n' "$*"; }

[[ "$THRESHOLD" =~ ^[1-9][0-9]*$ ]] || { log 'FAIL: RECOVERY_FAILURE_THRESHOLD must be a positive integer'; exit 2; }
[[ "$MAX_RESTARTS" =~ ^[1-9][0-9]*$ ]] || { log 'FAIL: RECOVERY_MAX_RESTARTS_PER_WINDOW must be a positive integer'; exit 2; }
[[ "$WINDOW_SECONDS" =~ ^[1-9][0-9]*$ ]] || { log 'FAIL: RECOVERY_WINDOW_SECONDS must be a positive integer'; exit 2; }

count=0
[[ -f "$FAILURE_FILE" ]] && read -r count < "$FAILURE_FILE" || true
[[ "$count" =~ ^[0-9]+$ ]] || count=0

if systemctl is-active --quiet "$SERVICE"; then
  printf '0\n' > "$FAILURE_FILE"
  exit 0
fi

count=$((count + 1))
printf '%s\n' "$count" > "$FAILURE_FILE"
log "WARN: $SERVICE failure count $count/$THRESHOLD"
(( count < THRESHOLD )) && exit 1

now="$(date +%s)"
last_restart=0
restart_count=0
if [[ -f "$STATE_FILE" ]]; then
  read -r last_restart restart_count < "$STATE_FILE" || true
fi
[[ "$last_restart" =~ ^[0-9]+$ ]] || last_restart=0
[[ "$restart_count" =~ ^[0-9]+$ ]] || restart_count=0
if (( now - last_restart >= WINDOW_SECONDS )); then restart_count=0; fi
if (( restart_count >= MAX_RESTARTS )); then
  log "FAIL: restart limit reached; manual intervention required for $SERVICE"
  exit 1
fi

systemctl restart "$SERVICE"
printf '%s %s\n' "$now" "$((restart_count + 1))" > "$STATE_FILE"
sleep 5
if systemctl is-active --quiet "$SERVICE"; then
  printf '0\n' > "$FAILURE_FILE"
  log "PASS: $SERVICE recovered after restart"
  exit 0
fi

log "FAIL: $SERVICE did not recover after restart"
if [[ -n "${HEALTH_ALERT_WEBHOOK_URL:-}" ]] && command -v curl >/dev/null 2>&1; then
  payload="$(printf '%s' "$SERVICE did not recover after $count consecutive health-check failures" | python3 -c 'import json,sys; print(json.dumps({"text":sys.stdin.read()}))')"
  printf '%s' "$payload" | curl --fail --silent --show-error --max-time 10 \
    --header 'Content-Type: application/json' --data-binary @- \
    "$HEALTH_ALERT_WEBHOOK_URL" >/dev/null || log 'WARN: recovery webhook delivery failed'
fi
exit 1
