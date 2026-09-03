#!/usr/bin/env bash
# Enforce the monthly Azure budget from inside the runner VM.
#
# The old guard only looked for a hand-placed BUDGET_STOP file and logged
# "no automatic cost API without Billing Reader" every hour. It never stopped
# anything. August 2026 closed at 554.26 USD against a 150 USD budget.
#
# This version reads real month-to-date cost and acts on it. When the cost API
# is unreadable it falls back to a local ledger of running minutes so the guard
# still fails closed. A guard that cannot measure must not assume zero.
#
# Actions:
#   spend >= SOFT_PCT   log a warning and drop a BUDGET_WARN marker
#   spend >= HARD_PCT   stop the runner, write BUDGET_STOP, deallocate the VM
#
# BUDGET_STOP records the month it was written for. A stop from a previous
# month clears itself so the runner comes back on the first of the month.
set -uo pipefail

CONF=/etc/webkit-dnd/budget.env
# shellcheck disable=SC1090
[[ -f "$CONF" ]] && { set -a; . "$CONF"; set +a; }

BUDGET_USD="${BUDGET_USD:-150}"
SOFT_PCT="${BUDGET_SOFT_PCT:-75}"
HARD_PCT="${BUDGET_HARD_PCT:-100}"
VM_HOURLY_USD="${VM_HOURLY_USD:-0.904}"
NON_COMPUTE_USD="${NON_COMPUTE_MONTHLY_USD:-36}"
MAX_INCREMENT_MIN="${LEDGER_MAX_INCREMENT_MIN:-20}"

CACHE="${WEBKIT_DND_CACHE:-/var/cache/webkit-dnd}"
STATE="$CACHE/out"
ETC=/etc/webkit-dnd
STOP="$ETC/BUDGET_STOP"
WARN="$ETC/BUDGET_WARN"
LOG=/var/log/webkit-dnd-budget-guard.log
RG="${AZURE_RG:-rg-webkit-dnd}"
VM="${AZURE_VM_NAME:-azure-webkit-dnd-d16}"

MONTH=$(date -u +%Y%m)
LEDGER="$STATE/budget-ledger-$MONTH"
SEEN="$STATE/budget-last-seen"

mkdir -p "$STATE" "$ETC" "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) budget guard ===="

now=$(date -u +%s)

# Clear a stop left over from an earlier month.
if [[ -f "$STOP" ]]; then
  stop_month=$(grep -m1 '^month=' "$STOP" 2>/dev/null | cut -d= -f2 || true)
  if [[ -n "$stop_month" && "$stop_month" != "$MONTH" ]]; then
    echo "clearing stale BUDGET_STOP from $stop_month"
    rm -f "$STOP" "$WARN"
  else
    echo "BUDGET_STOP active for $MONTH; ensuring VM is down"
  fi
fi

# --- local ledger of running minutes -----------------------------------------
# The guard only runs while the VM is allocated, so the gap between runs is
# running time. Cap the increment so a deallocated week is not billed to the
# ledger on the next boot.
prev=$(cat "$SEEN" 2>/dev/null || echo "")
if [[ "$prev" =~ ^[0-9]+$ ]] && (( now > prev )); then
  inc_min=$(( (now - prev) / 60 ))
  (( inc_min > MAX_INCREMENT_MIN )) && inc_min="$MAX_INCREMENT_MIN"
else
  inc_min=0
fi
echo "$now" > "$SEEN"

run_min=$(cat "$LEDGER" 2>/dev/null || echo 0)
[[ "$run_min" =~ ^[0-9]+$ ]] || run_min=0
run_min=$(( run_min + inc_min ))
echo "$run_min" > "$LEDGER"

ledger_cost=$(awk -v m="$run_min" -v r="$VM_HOURLY_USD" -v n="$NON_COMPUTE_USD" \
  'BEGIN { printf "%.2f", (m / 60.0) * r + n }')
echo "ledger running_minutes=$run_min estimate=${ledger_cost} USD"

# --- authoritative cost ------------------------------------------------------
az login --identity >/dev/null 2>&1 || true
[[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]] && \
  az account set --subscription "$AZURE_SUBSCRIPTION_ID" >/dev/null 2>&1 || true

source_used=ledger
spend="$ledger_cost"
if api_cost=$(/usr/local/sbin/azure-cost-mtd.sh 2>/dev/null); then
  if [[ "$api_cost" =~ ^[0-9.]+$ ]]; then
    source_used=costapi
    spend="$api_cost"
  fi
fi
echo "spend=${spend} USD source=${source_used} budget=${BUDGET_USD} USD month=${MONTH}"

pct=$(awk -v s="$spend" -v b="$BUDGET_USD" 'BEGIN { if (b <= 0) print 0; else printf "%.1f", (s / b) * 100 }')
echo "consumed=${pct}% soft=${SOFT_PCT}% hard=${HARD_PCT}%"

over() { awk -v p="$pct" -v t="$1" 'BEGIN { exit !(p >= t) }'; }

if over "$HARD_PCT"; then
  echo "HARD BREACH ${pct}% >= ${HARD_PCT}%; stopping runner and deallocating"
  {
    echo "month=$MONTH"
    echo "written=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "spend=$spend"
    echo "budget=$BUDGET_USD"
    echo "source=$source_used"
    echo "reason=monthly budget exhausted"
  } > "$STOP"
  chmod 0644 "$STOP"

  systemctl stop 'actions.runner.*.service' 2>/dev/null || true
  systemctl disable --now webkit-dnd-cache-sync.timer 2>/dev/null || true

  if [[ -x /usr/local/sbin/docker-seed-export.sh ]]; then
    timeout 300 /usr/local/sbin/docker-seed-export.sh || true
  fi
  if az vm deallocate -g "$RG" -n "$VM"; then
    echo "DEALLOCATED on budget breach"
    exit 0
  fi
  echo "deallocate failed after budget breach" >&2
  exit 1
fi

if over "$SOFT_PCT"; then
  echo "SOFT WARN ${pct}% >= ${SOFT_PCT}%"
  {
    echo "month=$MONTH"
    echo "written=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "spend=$spend"
    echo "pct=$pct"
  } > "$WARN"
  exit 0
fi

rm -f "$WARN"
echo "within budget"
exit 0
