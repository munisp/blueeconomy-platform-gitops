#!/usr/bin/env bash
set -Eeuo pipefail

OUT_FILE="${1:-/var/log/blueeconomy-pr-monitor-security-$(date -u +%Y%m%dT%H%M%SZ).log}"
mkdir -p "$(dirname "$OUT_FILE")"

{
  printf '%s\n' 'Blue Economy PR monitor systemd security report'
  printf 'Generated UTC: %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for unit in \
    blueeconomy-pr-approval-monitor.service \
    blueeconomy-pr-approval-monitor-health.service; do
    printf '%s\n' "=== $unit: active properties ==="
    systemctl show "$unit" \
      -p LoadState -p ActiveState -p SubState -p User -p Group \
      -p NoNewPrivileges -p PrivateTmp -p PrivateDevices -p ProtectSystem \
      -p ProtectHome -p ProtectKernelTunables -p ProtectKernelModules \
      -p ProtectKernelLogs -p ProtectControlGroups -p ProtectClock \
      -p ProtectHostname -p RestrictRealtime -p RestrictAddressFamilies \
      -p RestrictNamespaces -p RestrictSUIDSGID -p LockPersonality \
      -p RemoveIPC -p KeyringMode -p ProcSubset -p ProtectProc \
      -p CapabilityBoundingSet -p AmbientCapabilities -p SystemCallFilter \
      -p SystemCallErrorNumber -p UMask -p ReadWritePaths
    printf '\n%s\n' "=== $unit: systemd-analyze security ==="
    systemd-analyze security --no-pager "$unit" || true
    printf '\n'
  done
} | tee "$OUT_FILE"

chmod 0640 "$OUT_FILE"
printf 'Report written to %s\n' "$OUT_FILE"
