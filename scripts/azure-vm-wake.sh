#!/usr/bin/env bash
# Start Azure runner VM; wait until Listener is actually accepting jobs.
# GITHUB_TOKEN cannot list runners (403) — use Azure Run Command.
set -euo pipefail

RG="${AZURE_RG:-RG-WEBKIT-DND}"
VM="${AZURE_VM_NAME:-azure-webkit-dnd-d16}"
RUNNER_NAME="${AZURE_RUNNER_NAME:-azure-d16ds-webkit-dnd}"
REPO="${GITHUB_REPOSITORY:-sirredbeard/WebKitGTK-DND-Fix}"
WAIT_SECS="${AZURE_WAKE_WAIT_SECS:-600}"
STATIC_IP="${AZURE_STATIC_IP:-20.127.61.97}"

if ! az account show >/dev/null 2>&1; then
  if [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" && -n "${AZURE_TENANT_ID:-}" ]]; then
    az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" >/dev/null
  elif [[ -f /etc/webkit-dnd/azure.env ]]; then
    set -a; source /etc/webkit-dnd/azure.env; set +a
    az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" >/dev/null
  else
    echo "azure not logged in and no SP env" >&2
    exit 1
  fi
fi
[[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]] && az account set --subscription "$AZURE_SUBSCRIPTION_ID"

echo "starting vm $VM in $RG"
az vm start -g "$RG" -n "$VM" >/dev/null
POWER=$(az vm get-instance-view -g "$RG" -n "$VM" --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv)
echo "power=$POWER"
IP=$(az vm show -g "$RG" -n "$VM" -d --query publicIps -o tsv 2>/dev/null || true)
echo "publicIp=${IP:-$STATIC_IP}"

probe_and_fix() {
  az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript --scripts "set -e
if [[ ! -f /etc/sudoers.d/90-webkit-dnd-gha ]]; then
  if [[ -x /usr/local/sbin/install-gha-sudoers.sh ]]; then /usr/local/sbin/install-gha-sudoers.sh || true
  else echo 'gha ALL=(root) NOPASSWD:ALL' > /etc/sudoers.d/90-webkit-dnd-gha; chmod 440 /etc/sudoers.d/90-webkit-dnd-gha; fi
fi
if [[ -x /usr/local/sbin/azure-runner-health.sh ]]; then RUNNER_LOG_STALE_SEC=120 /usr/local/sbin/azure-runner-health.sh || true; fi
SVC=\$(systemctl list-units --type=service --state=running 'actions.runner.*' --no-legend | awk '{print \$1}' | head -1 || true)
if [[ -z \"\$SVC\" ]]; then
  SVC=\$(systemctl list-units --type=service --all 'actions.runner.*' --no-legend | awk '{print \$1}' | head -1 || true)
  [[ -n \"\$SVC\" ]] && systemctl reset-failed \"\$SVC\" 2>/dev/null || true
  [[ -n \"\$SVC\" ]] && systemctl restart \"\$SVC\" || true
  sleep 5
fi
ok=0
for i in 1 2 3 4 5 6 7 8; do
  if pgrep -f Runner.Listener >/dev/null 2>&1; then
    diag=\$(ls -t /opt/actions-runner/_diag/Runner_*.log 2>/dev/null | head -1 || true)
    if [[ -n \"\$diag\" ]] && grep -q 'Listening for Jobs' \"\$diag\" 2>/dev/null; then
      age=\$(( \$(date +%s) - \$(stat -c %Y \"\$diag\") ))
      if tail -n 80 \"\$diag\" | grep -q 'Listening for Jobs' || [[ \"\$age\" -lt 300 ]]; then ok=1; break; fi
    fi
  fi
  sleep 5
done
mkdir -p /var/cache/webkit-dnd/out
date -u +%s > /var/cache/webkit-dnd/out/last-runner-activity
chown gha:docker /var/cache/webkit-dnd/out/last-runner-activity 2>/dev/null || true
rm -f /etc/webkit-dnd/HOLD_AWAKE
[[ -x /usr/local/sbin/docker-seed-load.sh ]] && /usr/local/sbin/docker-seed-load.sh || true
[[ -x /usr/local/sbin/docker-ephemeral-enable.sh ]] && AUTO_DOCKER_EPHEMERAL_HOURS=2 /usr/local/sbin/docker-ephemeral-enable.sh || true
if [[ \"\$ok\" -eq 1 ]]; then echo RUNNER_LISTENING_OK; pgrep -af Runner.Listener | head -2 || true; exit 0; fi
echo RUNNER_NOT_LISTENING; pgrep -af Runner.Listener | head -2 || true; exit 1
" --query 'value[0].message' -o tsv 2>/dev/null || true
}

gh_runner_online() {
  [[ -n "${GH_TOKEN:-}" ]] && command -v gh >/dev/null || return 1
  local status
  status=$(gh api "repos/${REPO}/actions/runners" --jq ".runners[] | select(.name==\"${RUNNER_NAME}\") | .status" 2>/dev/null || true)
  [[ "$status" == "online" ]]
}

deadline=$((SECONDS + WAIT_SECS))
sleep 15
attempt=0
while (( SECONDS < deadline )); do
  attempt=$((attempt + 1))
  POWER=$(az vm get-instance-view -g "$RG" -n "$VM" --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>/dev/null || true)
  echo "power=${POWER:-unknown} elapsed=${SECONDS}s attempt=${attempt}"
  if gh_runner_online; then
    out=$(probe_and_fix || true); echo "$out" | tail -20
    echo "WAKE_OK runner online via gh api"; exit 0
  fi
  if [[ "$POWER" == *"running"* ]]; then
    out=$(probe_and_fix || true); echo "$out" | tail -30
    if echo "$out" | grep -q 'RUNNER_LISTENING_OK'; then echo "WAKE_OK runner listening"; exit 0; fi
    if echo "$out" | grep -q 'Runner.Listener'; then echo "WAKE_OK runner process present"; exit 0; fi
  fi
  sleep 15
done
echo "WAKE_TIMEOUT runner not up within ${WAIT_SECS}s" >&2
exit 1
