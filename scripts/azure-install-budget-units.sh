#!/usr/bin/env bash
# Install the budget enforcement and idle control units on the Azure runner VM.
#
# Run as root on the VM. Copies the control scripts into /usr/local/sbin, writes
# the budget policy, and replaces the systemd units.
#
#   SRC_DIR=/path/to/repo/scripts ./azure-install-budget-units.sh
#
# What changes against the pre-September 2026 setup:
#   - webkit-dnd-azure-budget-guard.sh (a no-op that logged "no stop" hourly)
#     is replaced by azure-budget-guard.sh, which reads real cost.
#   - The budget guard runs every 10 minutes instead of hourly.
#   - The runner health check runs every 5 minutes instead of every 2, and can
#     no longer flap.
#   - The hourly cache sync timer is removed. Peer sync is job driven now.
set -euo pipefail

SRC_DIR="${SRC_DIR:-$(cd "$(dirname "$0")" && pwd)}"
SBIN=/usr/local/sbin
ETC=/etc/webkit-dnd
UNITS=/etc/systemd/system

BUDGET_USD="${BUDGET_USD:-150}"
BUDGET_SOFT_PCT="${BUDGET_SOFT_PCT:-75}"
BUDGET_HARD_PCT="${BUDGET_HARD_PCT:-100}"
IDLE_MINUTES="${IDLE_MINUTES:-20}"
MAX_AWAKE_HOURS="${MAX_AWAKE_HOURS:-8}"
AZURE_RG="${AZURE_RG:-rg-webkit-dnd}"
AZURE_VM_NAME="${AZURE_VM_NAME:-azure-webkit-dnd-d16}"
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"

if [[ $EUID -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi

mkdir -p "$SBIN" "$ETC"

echo "+ installing control scripts from $SRC_DIR"
for f in azure-idle-watchdog.sh azure-runner-health.sh azure-budget-guard.sh azure-cost-mtd.sh; do
  if [[ -f "$SRC_DIR/$f" ]]; then
    install -m 0755 "$SRC_DIR/$f" "$SBIN/$f"
    echo "  installed $f"
  else
    echo "  missing $f in $SRC_DIR" >&2
  fi
done

echo "+ retiring the old no-op budget guard"
rm -f "$SBIN/webkit-dnd-azure-budget-guard.sh"

echo "+ writing budget policy"
cat > "$ETC/budget.env" << ENV
# Monthly Azure budget policy for this project.
# August 2026 closed at 554.26 USD against this number because nothing
# enforced it. The guard now deallocates at the hard threshold.
BUDGET_USD=${BUDGET_USD}
BUDGET_SOFT_PCT=${BUDGET_SOFT_PCT}
BUDGET_HARD_PCT=${BUDGET_HARD_PCT}
VM_HOURLY_USD=0.904
NON_COMPUTE_MONTHLY_USD=36
AZURE_RG=${AZURE_RG}
AZURE_VM_NAME=${AZURE_VM_NAME}
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
ENV
chmod 0644 "$ETC/budget.env"

echo "+ writing units"

cat > "$UNITS/webkit-dnd-idle-watchdog.service" << UNIT
[Unit]
Description=Deallocate the Azure runner when project work stops
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=-${ETC}/budget.env
Environment=IDLE_MINUTES=${IDLE_MINUTES}
Environment=MAX_AWAKE_HOURS=${MAX_AWAKE_HOURS}
Environment=LOCK_MAX_AGE_MIN=240
ExecStart=${SBIN}/azure-idle-watchdog.sh
UNIT

cat > "$UNITS/webkit-dnd-idle-watchdog.timer" << 'UNIT'
[Unit]
Description=Check Azure runner idle every 5 minutes

[Timer]
OnBootSec=10min
OnUnitActiveSec=5min
AccuracySec=30s
Persistent=true

[Install]
WantedBy=timers.target
UNIT

cat > "$UNITS/webkit-dnd-budget-guard.service" << UNIT
[Unit]
Description=Enforce the monthly Azure budget
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=-${ETC}/budget.env
ExecStart=${SBIN}/azure-budget-guard.sh
UNIT

cat > "$UNITS/webkit-dnd-budget-guard.timer" << 'UNIT'
[Unit]
Description=Budget guard every 10 minutes

[Timer]
OnBootSec=3min
OnUnitActiveSec=10min
AccuracySec=30s
Persistent=true

[Install]
WantedBy=timers.target
UNIT

cat > "$UNITS/webkit-dnd-runner-health.service" << UNIT
[Unit]
Description=Restart a wedged GitHub Actions runner listener
After=network-online.target

[Service]
Type=oneshot
Environment=MAX_RESTARTS_PER_HOUR=4
ExecStart=${SBIN}/azure-runner-health.sh
UNIT

cat > "$UNITS/webkit-dnd-runner-health.timer" << 'UNIT'
[Unit]
Description=Runner health every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
AccuracySec=30s
Persistent=true

[Install]
WantedBy=timers.target
UNIT

echo "+ removing the hourly peer sync timer"
systemctl disable --now webkit-dnd-cache-sync.timer 2>/dev/null || true
rm -f "$UNITS/webkit-dnd-cache-sync.timer"

systemctl daemon-reload
systemctl enable --now webkit-dnd-idle-watchdog.timer
systemctl enable --now webkit-dnd-budget-guard.timer
systemctl enable --now webkit-dnd-runner-health.timer

echo "+ active timers"
systemctl list-timers --all --no-pager | grep -i webkit || true
echo "install done"
