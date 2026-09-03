#!/usr/bin/env bash
# Deallocate the Azure runner VM once it stops doing project work.
#
# Run from a systemd timer on the Azure host only.
#
# The old watchdog trusted a single activity stamp that maintenance jobs wrote
# themselves. The health check restarted the runner every six minutes and
# stamped the file each time, so the idle clock reset forever and the VM stayed
# allocated from 8 August to 1 September. Cost was 554.26 USD against a 150 USD
# budget.
#
# Rules now:
#   - Only real project work counts: a Runner.Worker process, or a workflow
#     container. Maintenance timers no longer write the stamp.
#   - A hard uptime ceiling applies regardless of the stamp. Nothing may keep
#     this VM allocated indefinitely.
#   - The ceiling defers for work actually in flight, up to a second and larger
#     ceiling it cannot defer past. Killing a running build wastes the compute
#     already spent on it and the machine gets woken again to redo the work, so
#     a ceiling that ignores live work can cost more than it saves.
#   - Locks expire. A forgotten HOLD_AWAKE must not bill a month of compute.
#   - A budget stop always wins.
set -euo pipefail

IDLE_MINUTES="${IDLE_MINUTES:-20}"
MAX_AWAKE_HOURS="${MAX_AWAKE_HOURS:-8}"
# The ceiling waits for live work, but never past this. A build that has not
# finished in this long is wedged, and a wedged build is not worth paying for.
MAX_AWAKE_HOURS_HARD="${MAX_AWAKE_HOURS_HARD:-12}"
LOCK_MAX_AGE_MIN="${LOCK_MAX_AGE_MIN:-240}"
CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
STAMP="${CACHE}/out/last-runner-activity"
WORK_STAMP="${CACHE}/out/last-real-work"
LOCK_MAINT="/etc/webkit-dnd/MAINTENANCE_LOCK"
LOCK_HOLD="/etc/webkit-dnd/HOLD_AWAKE"
STOP="/etc/webkit-dnd/BUDGET_STOP"
LOG=/var/log/webkit-dnd-idle-watchdog.log
RG="${AZURE_RG:-rg-webkit-dnd}"
VM="${AZURE_VM_NAME:-azure-webkit-dnd-d16}"

mkdir -p "$(dirname "$STAMP")" "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) idle watchdog ===="

now=$(date -u +%s)

deallocate() {
  local why="$1"
  echo "deallocating: ${why}"
  systemctl stop 'actions.runner.*.service' 2>/dev/null || true
  if command -v az >/dev/null; then
    az login --identity >/dev/null 2>&1 || true
    if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
      az account set --subscription "$AZURE_SUBSCRIPTION_ID" >/dev/null 2>&1 || true
    fi
    # Persist the builder image off ephemeral before /mnt is lost.
    if [[ -x /usr/local/sbin/docker-seed-export.sh ]]; then
      timeout 300 /usr/local/sbin/docker-seed-export.sh || true
    fi
    az vm deallocate -g "$RG" -n "$VM" && { echo DEALLOCATED; exit 0; }
  fi
  echo "az deallocate failed" >&2
  exit 1
}

# A budget stop outranks every other signal, including locks.
if [[ -f "$STOP" ]]; then
  deallocate "budget stop present"
fi

# Real work only. A live worker or a workflow container is work in flight.
# Computed before the ceiling because the ceiling defers to it.
busy=""
if pgrep -f 'Runner.Worker' >/dev/null 2>&1; then
  busy="Runner.Worker live"
elif docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null | grep -Eqi 'webkit|dnd'; then
  busy="workflow container live"
fi

# Uptime ceiling. This is the backstop that the old design lacked.
#
# It defers while work is in flight. Deallocating a running build throws away
# the compute already spent on it, and the machine only gets woken again to
# redo the same work, so a ceiling that ignores live work can cost more than it
# saves. The deferral is bounded by a hard ceiling so this cannot become the
# indefinite hold the old watchdog had.
uptime_sec=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
uptime_h=$(( uptime_sec / 3600 ))
echo "uptime_hours=${uptime_h} ceiling=${MAX_AWAKE_HOURS} hard=${MAX_AWAKE_HOURS_HARD} busy=${busy:-no}"
if (( uptime_h >= MAX_AWAKE_HOURS_HARD )); then
  deallocate "uptime ${uptime_h}h reached hard ceiling ${MAX_AWAKE_HOURS_HARD}h"
fi
if (( uptime_h >= MAX_AWAKE_HOURS )); then
  if [[ -n "$busy" ]]; then
    echo "uptime ${uptime_h}h past ceiling ${MAX_AWAKE_HOURS}h but ${busy}; deferring"
  else
    deallocate "uptime ${uptime_h}h reached ceiling ${MAX_AWAKE_HOURS}h"
  fi
fi

# Locks hold the machine awake, but only for a bounded time.
for lock in "$LOCK_MAINT" "$LOCK_HOLD"; do
  [[ -f "$lock" ]] || continue
  age_min=$(( (now - $(stat -c %Y "$lock" 2>/dev/null || echo "$now")) / 60 ))
  if (( age_min >= LOCK_MAX_AGE_MIN )); then
    echo "lock $(basename "$lock") is ${age_min}m old; expiring it"
    rm -f "$lock"
    continue
  fi
  echo "lock $(basename "$lock") held ${age_min}m; skip"
  exit 0
done

if [[ -n "$busy" ]]; then
  echo "$now" > "$STAMP"
  echo "$now" > "$WORK_STAMP"
  echo "${busy}; refreshed activity"
  exit 0
fi

if [[ ! -f "$STAMP" ]]; then
  echo "$now" > "$STAMP"
  echo "initialized activity stamp"
  exit 0
fi

last=$(cat "$STAMP" 2>/dev/null || echo "$now")
[[ "$last" =~ ^[0-9]+$ ]] || last="$now"
# A stamp from the future means a clock skew or a bad writer. Do not trust it.
if (( last > now )); then
  echo "stamp is in the future; resetting to now"
  last="$now"
  echo "$now" > "$STAMP"
fi

idle=$(( (now - last) / 60 ))
echo "idle_minutes=$idle threshold=$IDLE_MINUTES"

if (( idle < IDLE_MINUTES )); then
  exit 0
fi

deallocate "idle ${idle}m >= ${IDLE_MINUTES}m"
