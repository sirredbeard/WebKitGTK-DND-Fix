# Budget and operations

Money and time boxes for the dual-runner setup. Product and engine design live elsewhere.

### Azure $150/month budget

Consumption budget `webkit-dnd-150` on resource group `rg-webkit-dnd`, amount **150**, timeGrain **Monthly**.

Notifications:

- Actual > 80%
- Actual > 100%
- Forecasted > 100%

Action group `ag-webkit-dnd-budget` emails the subscription user. Azure budgets do **not** hard-stop VMs by themselves. Pause path we wired:

- Hourly `webkit-dnd-budget-guard.timer` on the VM
- If `/etc/webkit-dnd/BUDGET_STOP` exists (or `FORCE_DEALLOCATE=1`), stop the runner service and `az vm deallocate` via managed identity
- When a budget email hits, either touch that file through `az vm run-command` or run `scripts/azure-vm-deallocate.sh` from the laptop

VS Enterprise credit behavior can also hard-limit the whole sub when credits are gone; treat the $150 budget as the decision alarm for this RG, not magic autoscaler math.

### Five-day Vultr exit hatch (runs on Azure)

systemd timer `webkit-dnd-vultr-snapshot-delete.timer` is active on Azure with `OnActiveSec=5d` from enable time (fires about five days out).

Service runs `/usr/local/sbin/webkit-dnd-vultr-snapshot-delete.sh` which:

1. Confirms API auth and that instance `3f9688ab-29c8-440a-a13e-ad6ded14792d` still exists
2. `vultr-cli snapshot create -i <id> -d webkit-dnd-gha-...`
3. Waits until snapshot status looks complete
4. `vultr-cli instance delete <id>`

API auth from Azure was tested live (`vultr-cli account info` and `instance get` succeeded) before arming the timer. Log: `/var/log/webkit-dnd-vultr-snapshot-delete.log`.

If we finish earlier, run the service manually or delete the timer. Snapshot is the recovery path if we still need that disk later.

### Vultr API allowlist

Azure static IP was added with the user IP whitelist API (POST `/v2/users/{id}/ip-whitelist` with subnet + subnet_size 32), same docs path as the console guide. Current useful entries include the laptop `/32` and `20.127.61.97/32`. Without that, `vultr-cli` on Azure gets blocked even with a valid key.

Vultr API key lives only under `/root/.config/vultr/` and `/etc/webkit-dnd/vultr.env` on Azure (mode 600). Not in the git repo. Not in GitHub Actions secrets (allowlist chicken-egg and no need).
