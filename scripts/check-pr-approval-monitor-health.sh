#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="${SERVICE_NAME:-blueeconomy-pr-approval-monitor.service}"
log() { logger -t blueeconomy-pr-monitor-health -- "$*" 2>/dev/null || true; printf '%s\n' "$*"; }
fail() { log "FAIL: $*"; exit 1; }

systemctl is-enabled --quiet "$SERVICE" || fail "$SERVICE is not enabled"
systemctl is-active --quiet "$SERVICE" || fail "$SERVICE is not active"

check_property() {
  local property="$1" expected="$2" actual
  actual="$(systemctl show "$SERVICE" --value -p "$property")"
  [[ "$actual" == "$expected" ]] || fail "$property expected '$expected' but is '$actual'"
}

check_property NoNewPrivileges yes
check_property PrivateTmp yes
check_property PrivateDevices yes
check_property ProtectSystem strict
check_property ProtectHome yes
check_property ProtectKernelTunables yes
check_property ProtectKernelModules yes
check_property ProtectKernelLogs yes
check_property ProtectControlGroups yes
check_property ProtectClock yes
check_property ProtectHostname yes
check_property RestrictRealtime yes
check_property RestrictNamespaces yes
check_property RestrictSUIDSGID yes
check_property LockPersonality yes
check_property RemoveIPC yes
check_property KeyringMode private
check_property ProcSubset pid
check_property ProtectProc invisible
check_property CapabilityBoundingSet ""
check_property AmbientCapabilities ""
check_property SystemCallFilter "@system-service"
check_property SystemCallErrorNumber EPERM
check_property UMask 0077

log "PASS: $SERVICE is active and required hardening properties are enforced"
