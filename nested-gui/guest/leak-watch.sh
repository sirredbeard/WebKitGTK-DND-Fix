#!/usr/bin/env bash
# Snapshot fds/portals; compare for canary and unexpected grants.
set -euo pipefail
OUT="${OUT_DIR:-/tmp/dnd-out}"
PHASE="${1:-pre}"
mkdir -p "$OUT/logs"
token=$(cat "$OUT/canary.token" 2>/dev/null || true)
{
  echo "phase=$PHASE time=$(date -u -Iseconds)"
  echo "doc_portal=$(ls -la /run/user/$(id -u)/doc 2>/dev/null | head -50 || true)"
  pgrep -a epiphany || true
  pid=$(pgrep -n epiphany || true)
  if [[ -n "$pid" ]]; then
    echo "fd_count=$(ls /proc/$pid/fd 2>/dev/null | wc -l)"
    ls -l /proc/$pid/fd 2>/dev/null | head -80 || true
  fi
} >"$OUT/logs/leak-$PHASE.txt"
if [[ -n "$token" ]]; then
  if grep -R --binary-files=without-match -F "$token" "$OUT" 2>/dev/null | grep -v canary.token | grep -v leak-pre | head; then
    echo '{"canary_leaked":true}' >"$OUT/leak-report.json"
  else
    echo '{"canary_leaked":false,"phase":"'"$PHASE"'"}' >"$OUT/leak-report.json"
  fi
fi
