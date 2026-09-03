#!/usr/bin/env bash
# Restart the GitHub Actions runner only when the listener is genuinely wedged.
#
# The previous version treated a stale _diag log as "wedged". An idle listener
# long-polls and writes nothing, so its log goes stale after a few minutes by
# design. The staleness test therefore fired forever: restart, fresh log, stale
# again about six minutes later, restart. It ran 5044 times and each restart
# refreshed the idle-watchdog activity stamp, which is why the VM never
# deallocated and August 2026 billed 554.26 USD.
#
# Rules now:
#   - A live Runner.Listener whose log ends in "Listening for Jobs" is healthy,
#     no matter how old that line is.
#   - Restart only for a dead unit, a missing listener process, or a sticky
#     broker backoff.
#   - Never write the activity stamp. Maintenance is not work. Only real jobs
#     may keep the machine awake.
#   - Rate limit restarts so a future flap cannot bill a month of compute.
set -euo pipefail

LOG=/var/log/webkit-dnd-runner-health.log
CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
STATE="$CACHE/out"
RESTART_LOG="$STATE/runner-restarts"
MAX_RESTARTS_PER_HOUR="${MAX_RESTARTS_PER_HOUR:-4}"

mkdir -p "$(dirname "$LOG")" "$STATE"
exec >>"$LOG" 2>&1
echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) runner-health ===="

if pgrep -f 'Runner.Worker' >/dev/null 2>&1; then
  echo "worker live; skip"
  exit 0
fi

if [[ -f /etc/webkit-dnd/BUDGET_STOP ]]; then
  echo "budget stop active; not restarting runner"
  exit 0
fi

SVC=$(systemctl list-units --type=service --all 'actions.runner.*' --no-legend 2>/dev/null | awk '{print $1}' | head -1 || true)
if [[ -z "$SVC" ]]; then
  echo "no actions.runner unit"
  exit 0
fi

need_restart=0
reason=""

if ! systemctl is-active --quiet "$SVC"; then
  need_restart=1
  reason="unit inactive"
elif ! pgrep -f 'Runner.Listener' >/dev/null 2>&1; then
  need_restart=1
  reason="listener process missing"
else
  diag=$(ls -t /opt/actions-runner/_diag/Runner_*.log 2>/dev/null | head -1 || true)
  if [[ -z "$diag" || ! -f "$diag" ]]; then
    # No log but a live listener is not proof of a wedge. Leave it alone.
    echo "listener live, no diag log; healthy"
  else
    age=$(( $(date +%s) - $(stat -c %Y "$diag") ))
    tail_txt=$(tail -n 40 "$diag" 2>/dev/null || true)
    # A stale log is normal for an idle listener. Only a backoff that never
    # returned to listening means the broker connection is stuck.
    if grep -q 'Listening for Jobs' <<<"$tail_txt"; then
      echo "diag=$diag age=${age}s listening; healthy"
    elif grep -q 'Back off' <<<"$tail_txt" && (( age > 600 )); then
      need_restart=1
      reason="sticky broker backoff, no listening line in ${age}s"
    else
      echo "diag=$diag age=${age}s no listening line yet; healthy"
    fi
  fi
fi

if (( need_restart == 0 )); then
  echo "healthy"
  exit 0
fi

# Rate limit. Keep only restarts from the last hour and refuse past the cap.
now=$(date +%s)
cutoff=$(( now - 3600 ))
if [[ -f "$RESTART_LOG" ]]; then
  awk -v c="$cutoff" '$1 ~ /^[0-9]+$/ && $1 >= c' "$RESTART_LOG" > "${RESTART_LOG}.tmp" 2>/dev/null || true
  mv -f "${RESTART_LOG}.tmp" "$RESTART_LOG" 2>/dev/null || true
fi
recent=$(wc -l < "$RESTART_LOG" 2>/dev/null || echo 0)
recent=${recent// /}
if (( recent >= MAX_RESTARTS_PER_HOUR )); then
  echo "restart suppressed: ${recent} restarts in the last hour >= ${MAX_RESTARTS_PER_HOUR} (${reason})"
  echo "flap detected; leaving runner alone so the idle watchdog can deallocate"
  exit 0
fi

echo "restarting $SVC (${reason})"
echo "$now" >> "$RESTART_LOG"
systemctl reset-failed "$SVC" 2>/dev/null || true
systemctl restart "$SVC"
sleep 4
systemctl is-active "$SVC" || true
pgrep -af Runner.Listener | head -2 || true
echo "restart done"
