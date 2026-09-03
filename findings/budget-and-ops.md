# Budget and operations

Money and time boxes for the dual-runner setup. Product and engine design live elsewhere.

### Azure $150/month budget

Consumption budget `webkit-dnd-150` on resource group `rg-webkit-dnd`, amount
**150**, timeGrain **Monthly**.

Notifications:

- Actual > 50%, 75%, 90% to `ag-webkit-dnd-notify` (email only)
- Forecasted > 100% to `ag-webkit-dnd-notify` (email only)
- Actual > 100% to `ag-webkit-dnd-budget` (email plus the deallocate runbook)

Five notifications is the Azure per-budget maximum. Spend them deliberately.
Only the actual 100% rule is wired to compute shutdown. A forecast is a
projection, not a fact, so it warns and nothing more. The warning ladder points
at a separate email-only action group on purpose. When every threshold shared
one action group, a 50% alert would have deallocated the runner at $75.

Azure budgets still do **not** stop compute on their own. A budget raises an
alert and an action group decides what that means. Ours now runs a runbook.

### Enforcement, in four independent layers

Any one of these can fail without the month running away.

1. **On-VM budget guard.** `scripts/azure-budget-guard.sh`, every 10 minutes.
   Reads real month-to-date cost through Cost Management. Warns at 75%.
   At 100% it writes `/etc/webkit-dnd/BUDGET_STOP`, stops the runner service,
   and deallocates. `BUDGET_STOP` records the month it was written for and
   clears itself when the month rolls, so the runner comes back on the first.
   When the cost API is unreadable the guard falls back to a local ledger of
   running minutes times the hourly rate. A guard that cannot measure must not
   assume zero.
2. **Azure budget alert to Automation runbook.** Automation account
   `aa-webkit-dnd-budget`, runbook `Stop-WebKitDndVm`, webhook `budget-stop`,
   attached to `ag-webkit-dnd-budget` as an automation runbook receiver. The
   runbook authenticates with its own system-assigned identity, which holds
   Virtual Machine Contributor on the resource group. It does not read anything
   from inside the VM, so it still works when the VM is wedged, misconfigured,
   or lying about its own state. Source is version controlled at
   `azure/runbooks/Stop-WebKitDndVm.ps1`.
3. **Hourly scheduled enforcement runbook.** Runbook
   `Enforce-WebKitDndBudget`, schedule `hourly-budget-check`, one hour
   interval, UTC. This is the strongest layer because it depends on nothing
   inside the VM and does not wait for a budget alert. Budget alerts lag by
   hours, which is enough time to burn a day of D16. The runbook queries Cost
   Management itself, groups the month by service, and separates compute from
   everything else. Compute over the budget means deallocate. It fails closed:
   if the cost query throws, it treats spend as infinite and deallocates
   anyway. It only ever deallocates, it never starts anything. Source is at
   `azure/runbooks/Enforce-WebKitDndBudget.ps1`.
4. **Native daily auto-shutdown.** `Microsoft.DevTestLab/schedules` on the VM,
   0300 UTC, enabled through `az vm auto-shutdown`. This is the dumbest layer
   and therefore the most reliable. It bounds a runaway to one day even if
   every script and alert above it is broken.

All four deallocate. Deallocate stops compute billing and keeps managed
disks, the static public IP, and everything under `/var/cache/webkit-dnd`.
Nothing is erased. Disks and IP still bill about $35 a month on their own.

The VM's managed identity needed **Cost Management Reader** at subscription
scope before any of this could read a real number. Virtual Machine Contributor
on the resource group is not enough, and the old guard said so in its log every
hour for three weeks without anyone acting on it.

VS Enterprise credit behavior can also hard-limit the whole sub when credits
are gone; treat the $150 budget as the decision alarm for this RG, not magic
autoscaler math.

### Verified 2026-09-02

Every layer was exercised, not just deployed.

- Cost reader as the VM identity returned `11.6793583668193` USD. Before the
  role grant this call failed.
- On-VM guard logged `spend=11.68 USD source=costapi consumed=7.8% within
  budget`. It is reading a real number now.
- Health check logged `age=707s listening; healthy` and did not restart. That
  is the exact condition that caused 5044 restarts in August.
- Idle watchdog was forced end to end and the VM deallocated.
- `Stop-WebKitDndVm` test job Completed, authenticated by managed identity,
  and correctly reported the VM already deallocated.
- `Enforce-WebKitDndBudget` test job Completed in 16 seconds and printed the
  per-service split: Virtual Machines 10.85, Storage 0.76, Virtual Network
  0.07, Azure Monitor 0.00, Bandwidth 0.00. It resolved compute 10.85 and
  non-compute 0.83, total 11.68 of 150, and left compute alone at 7.8 percent.
  The compute and storage split works.

The VM is deallocated. Vultr compute for this project is at zero.

### What the hourly check costs

Nothing worth measuring. The Automation account is Basic tier, which includes
500 free job minutes a month, then charges $0.002 a minute. A run takes about
13 to 16 seconds. Hourly is roughly 730 runs, so about 160 to 195 minutes a
month if Azure bills actual runtime. That is inside the free allowance. If
Azure rounds each job up to a whole minute the worst case is 730 minutes, 230
over the allowance, about $0.46 a month. Cost Management queries are free.

So the ceiling is under fifty cents a month to prevent another $400 overrun.
Do not lengthen the interval to save money.

### Postmortem: August 2026 closed at $554.26 against a $150 budget

Actual spend, all on the Visual Studio Enterprise subscription:

- `azure-webkit-dnd-d16`, D16ds_v5 in East US: $518.93
- `azure-webkit-dnd-os`, E20 SSD OS disk: $32.43
- `pip-webkit-dnd`, static IPv4: $2.86
- storage, SQL LTR, monitor: $0.04

The daily curve is the whole story. Nothing from 1 to 7 August. $20.70 on the
8th when the VM came up. Then $23.08 a day, flat, every day through the 31st.
A flat $21.696 of compute a day is $0.904 an hour times 24. The machine never
went down after 8 August. It ran 24 days at load average 0.00.

Two bugs, and they fed each other.

**The health check flapped.** `azure-runner-health.sh` treated a stale
`_diag` log as a wedged listener. An idle listener long-polls and writes
nothing, so its log goes stale after about six minutes by design. The staleness
test fired, restarted the runner, produced a fresh log, and then went stale
again six minutes later. It restarted the runner **5044 times**.

**Maintenance counted as work.** Every restart wrote
`/var/cache/webkit-dnd/out/last-runner-activity`. The idle watchdog measured
idleness from that file. So the idle clock reset every six minutes and never
reached its 30 minute threshold. The watchdog log shows `idle_minutes` walking
0, 1, 2, 3, 4, 5, 6, then back to 0, for three weeks. It was working exactly as
written. What it was told to measure was wrong.

**The budget guard was decorative.** It logged
`no automatic cost API without Billing Reader` and `no stop` once an hour,
every hour, and never queried a cost or stopped anything. It only looked for a
`BUDGET_STOP` file that a human had to place by hand. It was also never
committed to this repo, so nobody could review it.

Fixes, in the same order:

- The health check now treats a live listener whose log ends in
  `Listening for Jobs` as healthy no matter how old that line is. It restarts
  only for a dead unit, a missing listener process, or a sticky broker backoff
  that never returned to listening. Restarts are rate limited to four an hour.
  Past that it stops trying and lets the watchdog deallocate, because a flapping
  runner is a reason to release the machine, not to hold it.
- The health check and the daily seed no longer write the activity stamp.
  Maintenance is not project work. Only a `Runner.Worker` process or a workflow
  container refreshes the idle clock now.
- The watchdog gained a hard uptime ceiling of 8 hours that ignores the stamp
  entirely, lock expiry at 240 minutes so a forgotten `HOLD_AWAKE` cannot pin
  the VM, and a sanity check on stamps dated in the future. Idle threshold
  dropped from 30 minutes to 20.
- The budget guard reads real cost, and the two Azure-side layers above exist
  so that a broken guard is not the end of the story.

Lessons worth keeping:

- An idle process looks identical to a hung one if you only measure log age.
  Measure the thing you actually care about.
- Never let a maintenance job refresh the signal that decides whether
  maintenance is still needed. That is a loop with no exit.
- A cost guard without cost API permission is a log line, not a control. If a
  guard reports that it cannot measure, that report is a P1, not noise.
- Put the guard in the repo. Untracked infrastructure does not get reviewed.
- Alerts are not enforcement. Something has to act on them.

### Waking compute

Compute starts for project work only. `scripts/azure-vm-wake.sh` refuses to
start the VM unless a `WAKE_REASON` is set, which a workflow supplies through
`GITHUB_WORKFLOW`. It also reads month-to-date cost first and exits 3 when the
budget is already spent, because the VM cannot enforce its own budget while it
is deallocated.

Peer sync no longer runs on a timer. The hourly `webkit-dnd-cache-sync.timer`
is removed. `webkit-dnd-peer-sync.sh` exits unless it sees `GITHUB_RUN_ID` or
an explicit `SYNC_ON_DEMAND=1`. Syncing caches makes real jobs faster. It is
not a reason to hold a D16 allocated.


### Five-day Vultr exit hatch (runs on Azure)

systemd timer `webkit-dnd-vultr-snapshot-delete.timer` is active on Azure with `OnActiveSec=5d` from enable time (fires about five days out).

Service runs `/usr/local/sbin/webkit-dnd-vultr-snapshot-delete.sh` which:

1. Confirms API auth and that instance `3f9688ab-29c8-440a-a13e-ad6ded14792d` still exists
2. `vultr-cli snapshot create -i <id> -d webkit-dnd-gha-...`
3. Waits until snapshot status looks complete
4. `vultr-cli instance delete <id>`

API auth from Azure was tested live (`vultr-cli account info` and `instance get` succeeded) before arming the timer. Log: `/var/log/webkit-dnd-vultr-snapshot-delete.log`.

If we finish earlier, run the service manually or delete the timer. Snapshot is the recovery path if we still need that disk later.

Verified 2026-09-02. The hatch fired and did what it was supposed to do.
Snapshot `webkit-dnd-gha-final`, id `a6af62c4-7552-465e-8770-8523fea18506`,
created 2026-08-13, 500 GB raw and 47.9 GB compressed, status `complete`. The
runner instance is gone from `vultr-cli instance list`, no block storage
remains, and pending charges are $0.67. The only Vultr instances left are
unrelated personal boxes. Vultr compute for this project is at zero and the
Fedora runner is restorable from that snapshot.

### Vultr API allowlist

Azure static IP was added with the user IP whitelist API (POST `/v2/users/{id}/ip-whitelist` with subnet + subnet_size 32), same docs path as the console guide. Current useful entries include the laptop `/32` and `20.127.61.97/32`. Without that, `vultr-cli` on Azure gets blocked even with a valid key.

Vultr API key lives only under `/root/.config/vultr/` and `/etc/webkit-dnd/vultr.env` on Azure (mode 600). Not in the git repo. Not in GitHub Actions secrets (allowlist chicken-egg and no need).

### Watchdog ordering bug: the ceiling killed live builds

The idle watchdog deallocated the builder twice in the middle of a running
negative control matrix. The cause was check order, not policy.

The script evaluated the uptime ceiling before it evaluated whether the box was
busy. So once uptime crossed `MAX_AWAKE_HOURS`, a live multi-hour build was
deallocated on the next tick regardless of what it was doing. The busy check
existed and worked. It just never got to run.

The fix is not to delete the ceiling. The postmortem above is the reason the
ceiling exists at all: a forgotten wake kept the VM allocated from 8 August to
1 September and closed the month at $554.26 against a $150 budget. Removing the
ceiling would reintroduce exactly that failure.

Instead the ceiling now defers to live work, bounded. Order is:

1. Hard ceiling `MAX_AWAKE_HOURS_HARD`, default 12 hours. Deallocates
   unconditionally. Nothing defers this, including a `HOLD_AWAKE` lock.
2. Busy check. If real work is running, log and stay up.
3. Soft ceiling `MAX_AWAKE_HOURS`. Deallocates only when not busy.
4. Idle timeout.

So a legitimate long build gets to finish, a runaway is still capped at 12
hours instead of 24 days, and the $554 shape cannot recur. The worst case is
now roughly the cost of half a day, not most of a month.

Two operational notes learned alongside this:

- Not every deallocation during that period was wrong. Reviewing the logs
  afterwards, several were correct, because the build container had already
  exited on `PATCH FAILED` and the machine genuinely was idle. Read the log
  before blaming the watchdog.
- Containers do not survive deallocation, so anything you want to read later
  must be written to `/var/cache/webkit-dnd/`, which is on the persistent
  mount. Logs written inside a container are gone.

### The cloud runbook was deallocating live builds, and the lock could not stop it

A GTK3 compile got killed twice in twenty minutes with `HOLD_AWAKE` set. The
VM-local watchdog was not responsible either time. Worth writing down because
the diagnosis went down two wrong paths first.

Wrong path one: the idle watchdog. Its journal showed no run in the window.
Note the unit is `webkit-dnd-idle-watchdog`, not `azure-idle-watchdog`, and
querying the wrong name returns "No entries" rather than an error, which reads
like an alibi.

Wrong path two: `webkit-dnd-budget-guard` on the VM. It did run seconds before
the shutdown, which looked damning. It was not guilty. Its only `az vm
deallocate` call sits behind a hard breach that also writes
`/etc/webkit-dnd/BUDGET_STOP`, and that file was absent. Its ledger is
month-scoped (`budget-ledger-$MONTH`), so there is no August carryover either.

The actual cause was the Azure Automation runbook `Enforce-WebKitDndBudget` in
account `aa-webkit-dnd-budget`, on schedule `hourly-budget-check`, which fires
at :30 past every hour. The activity log names the caller as principal
`061dbf2c-976b-4e0b-99d7-c771156db47d`, and that is the automation account's
system assigned identity, which confirms it.

The runbook reads month-to-date cost, and it fails closed:

```
if ($null -eq $total) {
    Write-Warning "cost unreadable after 4 attempts; failing closed and deallocating"
    $total = [double]::MaxValue
}
```

The Cost Management query API is currently returning failures for that scope.
`azure-cost-mtd.sh` run on the VM exhausts all four attempts. So `$total`
became `MaxValue`, every hour, and the runbook deallocated a machine whose real
month-to-date spend was 23.24 USD against a 150 USD budget.

The identity is not the problem. It holds Cost Management Reader at
subscription scope and Virtual Machine Contributor on the resource group. The
same query run from an operator shell succeeded minutes earlier. This is
throttling. The Cost Management API has tight per-scope limits, and there are
three readers here: the operator, the VM guard, and the runbook.

Fail closed was the right instinct after August. Failing closed on a throttle
is not. A 429 does not mean the money is gone, it means ask later. And the
behaviour was not even conservative in cost terms: every hour the machine was
woken, did about twenty-five minutes of work, got deallocated mid-compile, and
the wake was billed for nothing. Enforcement that discards work and re-bills
the wake costs more than it saves.

Fix, now published to the runbook: keep failing closed, but only after the cost
API has been unreadable for `UnreadableRunsBeforeStop` consecutive runs,
default 3. On the hourly schedule that is roughly three hours blind before
compute stops. The count lives in automation variable `CostUnreadableStreak`
and is reset to 0 on any successful read. A single throttled hour now logs and
returns instead of killing the machine.

Two things to remember from this:

- A VM-local lock file cannot restrain a cloud-side enforcer. `HOLD_AWAKE` is
  invisible to Azure Automation. If a hold needs to survive the runbook, the
  runbook has to check something the runbook can see, such as a tag on the VM
  or an automation variable.
- There are more enforcers here than the four the earlier section describes.
  The full set now includes the DevTest Labs auto-shutdown schedule
  `shutdown-computevm-azure-webkit-dnd-d16` at 03:00 UTC daily, which is
  separate from everything above and will stop the VM overnight regardless.
  Check `az resource list -g RG-WEBKIT-DND` before concluding anything about
  who stopped a machine.

### Restoring enforcement after the runbook patch

Disabling `hourly-budget-check` stopped the runbook from killing live builds,
but it also meant nothing in the cloud was watching spend. That is a worse
failure mode than the one we were fixing, and it is easy to leave in place by
accident because nothing complains.

Sequence used to close it out, in this order:

1. Publish the patched runbook and confirm the published content is the patched
   content, not the draft. `az rest` GET on
   `.../runbooks/Enforce-WebKitDndBudget/content` should show
   `UnreadableRunsBeforeStop` and the `CostUnreadableStreak` reads and writes.
2. Confirm the automation variable `CostUnreadableStreak` exists and reads `0`.
   The runbook tolerates it being missing, but a missing variable means the
   streak never persists and the tolerance silently does nothing.
3. Only then re-enable the schedule.
4. Remove `/etc/webkit-dnd/HOLD_AWAKE`, unmask and start
   `webkit-dnd-budget-guard.timer` and `webkit-dnd-idle-watchdog.timer`, and
   confirm both report `active`.
5. Deallocate the VM and verify `PowerState/deallocated` rather than trusting
   the command's exit status.

Re-enabling the schedule first would have handed control back to the runbook
before confirming it had stopped failing closed.

Worth keeping as a habit: after any incident where an enforcement mechanism is
switched off to unblock work, the switch-off is itself an open item. It should
not be left to be noticed later.

## The fifth stop nobody knew about: Azure auto-shutdown, found 2026-09-03

A rebuild on the builder died at 03:01:26 UTC with the docker daemon
connection dropping and the VM deallocated a minute later. None of our four
layers did it. The idle watchdog was skipping on a fresh HOLD_AWAKE and saw a
live workflow container. The on-VM budget guard logged 15.5 percent, within
budget, at 03:00:18. The hourly Enforce-WebKitDndBudget job at 02:30 wrote
"leaving compute alone" and the next one did not run until 03:31. No GitHub
Actions run existed. The activity log named the caller as principal
c1c1a326-acb0-4543-99ec-252622aeebb2, application 1a14be2a-e903-4cec-99cf-b2e209259a0f,
which is "Azure Lab Services". That is the first-party identity behind the
VM auto-shutdown feature.

The VM had a DevTest Labs schedule, `shutdown-computevm-azure-webkit-dnd-d16`,
enabled, daily at 0300 UTC, task ComputeVmShutdownTask, notifications
disabled. 03:00 UTC is 23:00 Eastern. It was almost certainly set at VM
creation, where the portal offers auto-shutdown as a checkbox, and it has
been silently deallocating the machine at 11 PM Eastern ever since. In August
it did nothing visible because the runaway VM was woken again by the daily
seed; in September it killed a build.

It is disabled as of 2026-09-03, not deleted:

```
az rest --method patch --url "https://management.azure.com/subscriptions/<sub>/resourceGroups/RG-WEBKIT-DND/providers/Microsoft.DevTestLab/schedules/shutdown-computevm-azure-webkit-dnd-d16?api-version=2018-09-15" --body '{"properties":{"status":"Disabled"}}'
```

Reasoning, so nobody re-enables it as a cost measure: a wall-clock stop that
ignores in-flight work is the expensive kind. It throws away the compute
already spent and the machine gets woken again to redo it. The idle watchdog
already deallocates after 20 idle minutes and at an 8 hour ceiling that
defers for live work, and the two budget guards stop compute at the budget
from inside and outside the VM. Those cover idle and spend. The schedule
covered neither; it covered a time of day. Setting `status` back to Enabled
restores it if wanted, but pick a time no build can cross, and there is no
such time on a machine that only runs when someone starts a job.

Check for it on any future VM in this group:

```
az rest --method get --url "https://management.azure.com/subscriptions/<sub>/resourceGroups/RG-WEBKIT-DND/providers/Microsoft.DevTestLab/schedules?api-version=2018-09-15" --query 'value[].{name:name,status:properties.status,time:properties.dailyRecurrence.time}'
```

Related lesson from the same night: jobs launched by run-command rather than
by the Actions runner never refresh `last-runner-activity`, and the idle
watchdog handles HOLD_AWAKE before it refreshes the stamp, so a held machine
can look idle to anything else that reads the stamp. The `keepalive.sh` loop
that now accompanies a manual job touches HOLD_AWAKE and both stamps every two
minutes while the job container is alive. And `az vm start` alone does not
restore the builder image; the image lives on the ephemeral disk and
`docker-seed-load.sh` has to run after every start, which the wake script does
and a bare start does not.


## keepalive leaks HOLD_AWAKE after the job container exits, found 2026-09-03

`keepalive.sh` loops while the job container is alive, touching
`/etc/webkit-dnd/HOLD_AWAKE` and both activity stamps every two minutes. It
never removed the lock on exit. The rebasecheck container finished at
04:32:10Z and keepalive logged "container gone at 04:33:47", but the lock file
stayed, so the idle watchdog kept logging "lock HOLD_AWAKE held Nm; skip" on a
machine with no containers and a load average falling through 0.6.

The 240 minute lock expiry would have released it eventually. That is the
backstop, not the design. Four hours of an idle D16ds_v5 is real money for a
job that finished in one minute of wall clock after the tests.

Fixed on the builder by appending to `keepalive.sh`:

```
rm -f /etc/webkit-dnd/HOLD_AWAKE
echo "keepalive: released HOLD_AWAKE at $(date -u +%T)"
```

The stale lock from that run was removed by hand after confirming
`docker ps -q` was empty. The general rule: anything that takes the awake lock
releases it in the same script, and the release is guarded by an actual
container check, not by an assumption about who runs last. Ledger at the time
of the leak read running_minutes=441, 23.24 USD of the 150 USD month, 15.5%.

## Repo made public, 2026-09-03

The repo went public on 2026-09-03 after filing. Before the flip: both PR
URLs for our own pull request were rewritten to plain text so nothing in
this repo creates a backlink on it (file content does not backlink, but the
rule is no linkable form anywhere), all GitHub Actions workflows and
actionlint config were deleted, all workflow runs were already gone, and the
`archive` branch was deleted from GitHub. The packaging history survives
locally as branches `archive` and `backup-pre-squash` in the working
checkout. A secret scan found nothing. The builder VM's static IPs appear in
findings; the NSG pins inbound sources and fail2ban runs, and the IPs were
already in the threat model as reserved addresses.
