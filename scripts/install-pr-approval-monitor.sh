#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_ROOT="${SOURCE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
INSTALL_ROOT="${INSTALL_ROOT:-/opt/blueeconomy-platform-gitops}"
CONFIG_DIR="${CONFIG_DIR:-/etc/blueeconomy}"
STATE_DIR="${STATE_DIR:-/var/lib/blueeconomy}"
SERVICE_NAME="blueeconomy-pr-approval-monitor.service"
SERVICE_SRC="$SOURCE_ROOT/deploy/external/$SERVICE_NAME"
ENV_TEMPLATE="$SOURCE_ROOT/deploy/external/pr-monitor.env.example"
ENV_FILE="$CONFIG_DIR/pr-monitor.env"
SERVICE_DEST="/etc/systemd/system/$SERVICE_NAME"

fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
[[ "$(id -u)" -eq 0 ]] || fail 'run as root or through sudo'
command -v systemctl >/dev/null 2>&1 || fail 'systemctl is required'
command -v systemd-analyze >/dev/null 2>&1 || fail 'systemd-analyze is required'
[[ -f "$SERVICE_SRC" ]] || fail "service unit not found: $SERVICE_SRC"
[[ -f "$ENV_TEMPLATE" ]] || fail "environment template not found: $ENV_TEMPLATE"

install -d -o root -g root -m 0755 "$CONFIG_DIR"
install -d -o blueeconomy -g blueeconomy -m 0700 "$STATE_DIR" 2>/dev/null || {
  getent group blueeconomy >/dev/null 2>&1 || groupadd --system blueeconomy
  id blueeconomy >/dev/null 2>&1 || useradd --system --gid blueeconomy --home-dir /nonexistent --shell /usr/sbin/nologin blueeconomy
  chown blueeconomy:blueeconomy "$STATE_DIR"
  chmod 0700 "$STATE_DIR"
}

if [[ ! -e "$ENV_FILE" ]]; then
  install -o root -g root -m 0600 "$ENV_TEMPLATE" "$ENV_FILE"
  fail "created blank $ENV_FILE; populate it with the approved secret manager, then rerun"
fi

mode="$(stat -c '%a' "$ENV_FILE")"
[[ "$mode" == "600" || "$mode" == "400" ]] || fail "$ENV_FILE must have mode 600 or 400"
# Only check for blank required fields; never print their values.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
[[ -n "${SLACK_WEBHOOK_URL:-}" ]] || fail 'SLACK_WEBHOOK_URL is empty; refusing to start'
[[ "${WATCH_SECONDS:-}" =~ ^[1-9][0-9]*$ ]] || fail 'WATCH_SECONDS must be a positive integer'
[[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]] || fail 'GH_TOKEN or GITHUB_TOKEN is empty; configure external GitHub authentication'

install -d -o root -g root -m 0755 "$INSTALL_ROOT"
# Copy source without operator secret files or generated backup artifacts.
tar --exclude='deploy/external/.env' --exclude='deploy/external/pr-monitor.env' \
    --exclude='backups' --exclude='*.dump' -C "$SOURCE_ROOT" -cf - . | tar -C "$INSTALL_ROOT" -xf -
chown -R root:root "$INSTALL_ROOT"
chmod 0755 "$INSTALL_ROOT/scripts/approval-monitor-with-slack.sh" "$INSTALL_ROOT/scripts/check-pr-approvals.sh"
install -o root -g root -m 0644 "$SERVICE_SRC" "$SERVICE_DEST"
systemd-analyze verify "$SERVICE_DEST"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
systemctl --no-pager --full status "$SERVICE_NAME"
printf '%s\n' "Installed and started $SERVICE_NAME. Review with: journalctl -u $SERVICE_NAME -f"
