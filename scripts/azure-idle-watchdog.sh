#!/usr/bin/env bash
# Deallocate Azure runner VM after IDLE_MINUTES with no Actions work.
# Run from systemd timer every few minutes on the Azure host only.
set -euo pipefail

IDLE_MINUTES="${IDLE_MINUTES:-30}"
CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
STAMP="${CACHE}/out/last-runner-activity"
LOCK_MAINT="/etc/webkit-dnd/MAINTENANCE_LOCK"
LOCK_HOLD="/etc/webkit-dnd/HOLD_AWAKE"
LOG=/var/log/webkit-dnd-idle-watchdog.log
RG="${AZURE_RG:-rg-webkit-dnd}"
VM="${AZURE_VM_NAME:-azure-webkit-dnd-d16}"

mkdir -p "$(dirname "$STAMP")" "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) idle watchdog ===="

if [[ -f "$LOCK_MAINT" ]]; then
  echo "maintenance lock present; skip"
  exit 0
fi
if [[ -f "$LOCK_HOLD" ]]; then
  echo "hold-awake lock present; skip"
  exit 0
fi

# Active job worker => definitely busy
if pgrep -f 'Runner.Worker' >/dev/null 2>&1; then
  date -u +%s > "$STAMP"
  echo "Runner.Worker live; refreshed activity"
  exit 0
fi

# Docker build/test containers from our workflows
if docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null | grep -Eqi 'webkit|dnd'; then
  date -u +%s > "$STAMP"
  echo "webkit docker container live; refreshed activity"
  exit 0
fi

now=$(date -u +%s)
if [[ ! -f "$STAMP" ]]; then
  # First boot / no jobs yet: start idle clock now so we don't die immediately after wake
  echo "$now" > "$STAMP"
  echo "initialized activity stamp"
  exit 0
fi

last=$(cat "$STAMP" 2>/dev/null || echo "$now")
idle=$(( (now - last) / 60 ))
echo "idle_minutes=$idle threshold=$IDLE_MINUTES"

if (( idle < IDLE_MINUTES )); then
  exit 0
fi

echo "idle >= ${IDLE_MINUTES}m; deallocating $VM"
# Stop runner cleanly so GitHub marks offline quickly
systemctl stop 'actions.runner.*.service' 2>/dev/null || true

if command -v az >/dev/null; then
  az login --identity >/dev/null 2>&1 || true
  if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
    az account set --subscription "$AZURE_SUBSCRIPTION_ID" >/dev/null 2>&1 || true
  fi
  # Persist builder image off ephemeral before /mnt is lost
if [[ -x /usr/local/sbin/docker-seed-export.sh ]]; then
  timeout 300 /usr/local/sbin/docker-seed-export.sh || true
fi
az vm deallocate -g "$RG" -n "$VM" && echo DEALLOCATED && exit 0
fi

echo "az deallocate failed" >&2
exit 1
