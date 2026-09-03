#!/usr/bin/env bash
# Start (allocate) the Azure WebKit DnD runner VM. Compute bills only while running.
set -euo pipefail
RG="${AZURE_RG:-rg-webkit-dnd}"
VM="${AZURE_VM:-azure-webkit-dnd-d16}"
az vm start -g "$RG" -n "$VM"
az vm get-instance-view -g "$RG" -n "$VM" --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv
az vm show -g "$RG" -n "$VM" -d --query "{name:name,power:powerState,publicIp:publicIps,privateIp:privateIps,size:hardwareProfile.vmSize}" -o json
