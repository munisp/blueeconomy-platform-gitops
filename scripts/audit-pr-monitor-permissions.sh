#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${INSTALL_ROOT:-/opt/blueeconomy-platform-gitops}"
CONFIG_DIR="${CONFIG_DIR:-/etc/blueeconomy}"
STATE_DIR="${STATE_DIR:-/var/lib/blueeconomy}"
LOG_DIR="${LOG_DIR:-/var/log/blueeconomy}"
FAILURES=0

check_path() {
  local path="$1" owner="$2" group="$3" mode="$4" kind="${5:-file}" actual_owner actual_group actual_mode
  if [[ "$kind" == directory && ! -d "$path" ]] || [[ "$kind" != directory && ! -f "$path" ]]; then
    printf 'FAIL missing %s\n' "$path"; FAILURES=$((FAILURES + 1)); return
  fi
  actual_owner="$(stat -c '%U' "$path")"
  actual_group="$(stat -c '%G' "$path")"
  actual_mode="$(stat -c '%a' "$path")"
  if [[ "$actual_owner:$actual_group:$actual_mode" != "$owner:$group:$mode" ]]; then
    printf 'FAIL %s owner=%s:%s mode=%s expected=%s:%s:%s\n' "$path" "$actual_owner" "$actual_group" "$actual_mode" "$owner" "$group" "$mode"
    FAILURES=$((FAILURES + 1))
  else
    printf 'PASS %s owner=%s:%s mode=%s\n' "$path" "$actual_owner" "$actual_group" "$actual_mode"
  fi
}

[[ "$(id -u)" -eq 0 ]] || { printf 'ERROR: run as root\n' >&2; exit 2; }

check_path "$ROOT" root root 755 directory
check_path "$ROOT/scripts" root root 755 directory
for script in approval-monitor-with-slack.sh check-pr-approvals.sh check-pr-approval-monitor-health.sh; do
  check_path "$ROOT/scripts/$script" root root 755 file
done
check_path "$CONFIG_DIR" root root 700 directory
check_path "$CONFIG_DIR/pr-monitor.env" root root 600 file
check_path "$STATE_DIR" blueeconomy blueeconomy 700 directory
check_path "$LOG_DIR" blueeconomy blueeconomy 750 directory
for log in pr-monitor.log pr-monitor-health.log; do
  [[ -e "$LOG_DIR/$log" ]] && check_path "$LOG_DIR/$log" blueeconomy blueeconomy 640 file || printf 'INFO %s not created yet\n' "$LOG_DIR/$log"
done
for unit in blueeconomy-pr-approval-monitor.service blueeconomy-pr-approval-monitor-health.service blueeconomy-pr-approval-monitor-health.timer; do
  check_path "/etc/systemd/system/$unit" root root 644 file
done

if (( FAILURES > 0 )); then
  printf 'AUDIT_FAIL failures=%d\n' "$FAILURES"; exit 1
fi
printf '%s\n' 'AUDIT_PASS all present paths match expected ownership and modes'
