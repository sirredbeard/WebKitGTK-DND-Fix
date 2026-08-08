#!/usr/bin/env bash
# Restart GitHub Actions runner if Listener is wedged:
# - unit active but diag log stale with sticky broker errors, or
# - Listener process missing while unit claims active
# Skip while Runner.Worker is running a job.
set -euo pipefail
LOG=/var/log/webkit-dnd-runner-health.log
STALE_SEC="${RUNNER_LOG_STALE_SEC:-180}"
mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) runner-health ===="

if pgrep -f 'Runner.Worker' >/dev/null 2>&1; then
  echo "worker live; skip"
  exit 0
fi

SVC=$(systemctl list-units --type=service --all 'actions.runner.*' --no-legend 2>/dev/null | awk '{print $1}' | head -1 || true)
if [[ -z "$SVC" ]]; then
  echo "no actions.runner unit"
  exit 0
fi

need_restart=0
if ! systemctl is-active --quiet "$SVC"; then
  echo "unit inactive"
  need_restart=1
fi

if ! pgrep -f 'Runner.Listener' >/dev/null 2>&1; then
  echo "Listener process missing"
  need_restart=1
fi

diag=$(ls -t /opt/actions-runner/_diag/Runner_*.log 2>/dev/null | head -1 || true)
if [[ -n "$diag" && -f "$diag" ]]; then
  age=$(( $(date +%s) - $(stat -c %Y "$diag") ))
  echo "diag=$diag age=${age}s"
  if (( age > STALE_SEC * 2 )); then
    if ! journalctl -u "$SVC" --since "5 minutes ago" --no-pager 2>/dev/null | grep -q 'Listening for Jobs'; then
      echo "diag stale ${age}s and no recent Listening; restart"
      need_restart=1
    fi
  fi
  if ! tail -30 "$diag" 2>/dev/null | grep -q 'Listening for Jobs'; then
    if tail -8 "$diag" 2>/dev/null | grep -q 'Back off'; then
      if (( age > 120 )); then
        echo "broker backoff sticky; restart"
        need_restart=1
      fi
    fi
  fi
else
  echo "no diag log"
  need_restart=1
fi

if (( need_restart == 0 )); then
  echo "healthy"
  exit 0
fi

echo "restarting $SVC"
systemctl reset-failed "$SVC" 2>/dev/null || true
systemctl restart "$SVC"
sleep 4
systemctl is-active "$SVC" || true
pgrep -af Runner.Listener | head -2 || true
mkdir -p /var/cache/webkit-dnd/out
date -u +%s > /var/cache/webkit-dnd/out/last-runner-activity
chown gha:docker /var/cache/webkit-dnd/out/last-runner-activity 2>/dev/null || true
echo "restart done"
