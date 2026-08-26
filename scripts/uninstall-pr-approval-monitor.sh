#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-/opt/blueeconomy-platform-gitops}"
CONFIG_DIR="${CONFIG_DIR:-/etc/blueeconomy}"
STATE_DIR="${STATE_DIR:-/var/lib/blueeconomy}"
SERVICE_NAME="blueeconomy-pr-approval-monitor.service"
HEALTH_SERVICE_NAME="blueeconomy-pr-approval-monitor-health.service"
HEALTH_TIMER_NAME="blueeconomy-pr-approval-monitor-health.timer"
RECOVERY_SERVICE_NAME="blueeconomy-pr-approval-monitor-recovery.service"
RECOVERY_TIMER_NAME="blueeconomy-pr-approval-monitor-recovery.timer"
LOGROTATE_NAME="blueeconomy-pr-approval-monitor"

fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
[[ "$(id -u)" -eq 0 ]] || fail 'run as root or through sudo'
[[ "${CONFIRM_UNINSTALL:-}" == YES ]] || fail 'set CONFIRM_UNINSTALL=YES to remove monitoring services'
command -v systemctl >/dev/null 2>&1 || fail 'systemctl is required'

systemctl disable --now "$HEALTH_TIMER_NAME" "$RECOVERY_TIMER_NAME" 2>/dev/null || true
systemctl stop "$HEALTH_SERVICE_NAME" "$RECOVERY_SERVICE_NAME" "$SERVICE_NAME" 2>/dev/null || true
systemctl disable "$HEALTH_SERVICE_NAME" "$RECOVERY_SERVICE_NAME" "$SERVICE_NAME" 2>/dev/null || true

rm -f \
  "/etc/systemd/system/$HEALTH_TIMER_NAME" \
  "/etc/systemd/system/$RECOVERY_TIMER_NAME" \
  "/etc/systemd/system/$RECOVERY_SERVICE_NAME" \
  "/etc/systemd/system/$HEALTH_SERVICE_NAME" \
  "/etc/systemd/system/$SERVICE_NAME" \
  "/etc/logrotate.d/$LOGROTATE_NAME"
systemctl daemon-reload
systemctl reset-failed "$HEALTH_SERVICE_NAME" "$SERVICE_NAME" 2>/dev/null || true

rm -f "$INSTALL_ROOT/scripts/check-pr-approval-monitor-health.sh" \
      "$INSTALL_ROOT/scripts/recover-pr-approval-monitor.sh" \
      "$INSTALL_ROOT/scripts/audit-pr-monitor-permissions.sh" \
      "$INSTALL_ROOT/scripts/report-pr-monitor-security.sh" \
      "$INSTALL_ROOT/scripts/approval-monitor-with-slack.sh" \
      "$INSTALL_ROOT/scripts/check-pr-approvals.sh"

if [[ "${REMOVE_INSTALL_ROOT:-}" == YES ]]; then
  case "$INSTALL_ROOT" in
    /opt/blueeconomy-platform-gitops) rm -rf -- "$INSTALL_ROOT" ;;
    *) fail 'refusing to remove unexpected INSTALL_ROOT; use the fixed default path' ;;
  esac
fi

if [[ "${REMOVE_STATE:-}" == YES ]]; then
  rm -rf -- "$STATE_DIR"
fi

if [[ "${REMOVE_CONFIG:-}" == YES ]]; then
  case "$CONFIG_DIR" in
    /etc/blueeconomy) rm -rf -- "$CONFIG_DIR" ;;
    *) fail 'refusing to remove unexpected CONFIG_DIR; use the fixed default path' ;;
  esac
else
  printf '%s\n' "Preserved operator configuration at $CONFIG_DIR"
fi

printf '%s\n' 'Monitoring units disabled and removed.'
printf '%s\n' 'Secrets and state were preserved unless REMOVE_CONFIG=YES and REMOVE_STATE=YES were supplied.'
