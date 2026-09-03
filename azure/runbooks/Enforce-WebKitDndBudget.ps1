<#
.SYNOPSIS
Halt WebKitGTK DnD compute when the month's spend reaches the budget.

.DESCRIPTION
This runs on a schedule inside Azure Automation, hourly, and does not depend on
anything inside the runner VM or on a budget alert arriving.

Budget alerts are the wrong thing to rely on alone. They are evaluated on
Microsoft's cadence and can land many hours after the money is spent. In August
2026 the alerts fired and nothing acted on them, and the month closed at
554.26 USD against a 150 USD budget. This runbook reads the cost itself and
acts on what it reads.

Policy:

  Compute stops at the budget. Storage does not.

We are willing to pay for storage above the budget. Keeping the ccache, the
prefix tarballs, and the build snapshots on disk is cheaper than recompiling
WebKit later on a D16. So this runbook only ever deallocates the VM. It never
deletes a disk, a snapshot, or a cache. Deallocate stops compute billing and
leaves managed disks, the static public IP, and /var/cache/webkit-dnd intact.

Because storage keeps billing after the stop, total monthly spend is expected
to drift past the budget by roughly the disk and IP cost. That overshoot is
deliberate and it is the cheap kind.

Authenticates with the automation account system assigned managed identity,
which holds Virtual Machine Contributor on the resource group and Cost
Management Reader on the subscription.
#>

param(
    [Parameter(Mandatory = $false)]
    [double] $BudgetUsd = 150.0,

    [Parameter(Mandatory = $false)]
    [string] $ResourceGroup = 'rg-webkit-dnd',

    [Parameter(Mandatory = $false)]
    [string] $VmName = 'azure-webkit-dnd-d16',

    # How many consecutive runs with an unreadable cost API before we stop
    # compute anyway. Hourly schedule, so 3 is roughly three hours blind.
    [Parameter(Mandatory = $false)]
    [int] $UnreadableRunsBeforeStop = 3
)

$ErrorActionPreference = 'Stop'

Write-Output "budget enforcement starting at $(Get-Date -Format o)"
Write-Output "budget: $BudgetUsd USD, compute stops at the budget, storage is exempt"

try {
    Disable-AzContextAutosave -Scope Process | Out-Null
    $ctx = (Connect-AzAccount -Identity).context
    $ctx = Set-AzContext -SubscriptionName $ctx.Subscription -DefaultProfile $ctx
}
catch {
    Write-Error "managed identity sign in failed: $_"
    throw
}

$subId = $ctx.Subscription.Id
$scope = "/subscriptions/$subId/resourceGroups/$ResourceGroup"
Write-Output "scope: $scope"

# Month to date actual cost, grouped by service so the log shows where the
# money went and so we can tell compute from storage.
$body = @{
    type      = 'ActualCost'
    timeframe = 'MonthToDate'
    dataSet   = @{
        granularity = 'None'
        aggregation = @{ totalCost = @{ name = 'Cost'; function = 'Sum' } }
        grouping    = @(@{ type = 'Dimension'; name = 'ServiceName' })
    }
} | ConvertTo-Json -Depth 10

$uri = "https://management.azure.com$scope/providers/Microsoft.CostManagement/query?api-version=2023-11-01"

$total = $null
for ($attempt = 1; $attempt -le 4; $attempt++) {
    try {
        $resp = Invoke-AzRestMethod -Method POST -Uri $uri -Payload $body -DefaultProfile $ctx
        if ($resp.StatusCode -eq 200) {
            $data = $resp.Content | ConvertFrom-Json
            $rows = $data.properties.rows
            $total = 0.0
            $compute = 0.0
            foreach ($r in $rows) {
                $cost = [double] $r[0]
                $svc = [string] $r[1]
                $total += $cost
                if ($svc -like '*Virtual Machines*') { $compute += $cost }
                Write-Output ("  {0,10:N2}  {1}" -f $cost, $svc)
            }
            $storage = $total - $compute
            Write-Output ("compute: {0:N2} USD, non-compute: {1:N2} USD" -f $compute, $storage)
            break
        }
        Write-Output "cost query returned HTTP $($resp.StatusCode), attempt $attempt"
    }
    catch {
        Write-Output "cost query attempt ${attempt} failed: $_"
    }
    Start-Sleep -Seconds (5 * $attempt)
}

if ($null -eq $total) {
    # Cannot measure. Do not assume zero, and do not assume the worst on the
    # first miss either.
    #
    # The Cost Management query API throttles. When several callers ask about
    # the same scope in the same minute, which happens here because an operator
    # and the runner VM both read cost too, every attempt in this loop can come
    # back 429. That is not evidence of spending. Treating it as a breach
    # deallocated a live build once an hour and still billed the wake, so the
    # fail-closed path was costing money rather than saving it.
    #
    # Still fail closed, just not instantly. Count consecutive unreadable runs
    # in an automation variable and act once the cost API has been unreadable
    # for long enough that it is a real outage rather than a throttle.
    $streak = 0
    try { $streak = [int] (Get-AutomationVariable -Name 'CostUnreadableStreak') } catch { $streak = 0 }
    $streak = $streak + 1
    try { Set-AutomationVariable -Name 'CostUnreadableStreak' -Value $streak } catch { }

    if ($streak -lt $UnreadableRunsBeforeStop) {
        Write-Warning "cost unreadable, consecutive run $streak of $UnreadableRunsBeforeStop; leaving compute alone this hour"
        return
    }

    Write-Warning "cost unreadable for $streak consecutive runs; failing closed and deallocating"
    $total = [double]::MaxValue
}
else {
    try { Set-AutomationVariable -Name 'CostUnreadableStreak' -Value 0 } catch { }
    Write-Output ("month to date total: {0:N2} USD of {1:N2} USD budget" -f $total, $BudgetUsd)
}

if ($total -lt $BudgetUsd) {
    $pct = [math]::Round(($total / $BudgetUsd) * 100, 1)
    Write-Output "within budget at $pct percent, leaving compute alone"
    return
}

Write-Output "budget reached, halting compute"

$vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VmName -Status -DefaultProfile $ctx
$power = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus
Write-Output "current power state: $power"

if ($power -eq 'VM deallocated') {
    Write-Output "already deallocated, nothing to do"
    return
}

Stop-AzVM -ResourceGroupName $ResourceGroup -Name $VmName -Force -DefaultProfile $ctx | Out-Null

$vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VmName -Status -DefaultProfile $ctx
$power = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus
Write-Output "final power state: $power"
Write-Output "disks, public IP, and build caches are retained on purpose"

