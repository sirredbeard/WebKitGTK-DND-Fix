#!/usr/bin/env bash
# Deallocate the Azure WebKit DnD runner VM.
# Stops compute billing. OS disk + public IP (if static) still bill a little.
set -euo pipefail
RG="${AZURE_RG:-rg-webkit-dnd}"
VM="${AZURE_VM:-azure-webkit-dnd-d16}"
# Prefer graceful stop of runner service if we can SSH
if [[ -n "${AZURE_SSH_HOST:-}" ]] || grep -q "Host azure-webkit-dnd" ~/.ssh/config 2>/dev/null; then
  HOST="${AZURE_SSH_HOST:-azure-webkit-dnd}"
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" \
    'sudo systemctl stop actions.runner.*.service 2>/dev/null || true' || true
fi
az vm deallocate -g "$RG" -n "$VM"
az vm get-instance-view -g "$RG" -n "$VM" --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv
echo "deallocated: compute not billing; disk/IP may still bill"
