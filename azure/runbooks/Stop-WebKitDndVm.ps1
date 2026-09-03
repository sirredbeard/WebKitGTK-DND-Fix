<#
.SYNOPSIS
Deallocate the WebKitGTK DnD runner VM when the monthly budget alert fires.

.DESCRIPTION
This runbook is the Azure side backstop for the monthly budget. It does not
depend on anything running inside the VM.

An Azure Consumption budget only sends notifications. It does not stop
compute. In August 2026 the budget was set to 150 USD, the alerts fired, and
the VM kept running because nothing acted on them. The month closed at
554.26 USD. This runbook is what turns the alert into an action.

It is called by the ag-webkit-dnd-budget action group through a webhook. The
budget alert payload is passed in $WebhookData, but the runbook does not
depend on parsing it: any invocation means a threshold was crossed, so it
deallocates.

Deallocate stops compute billing. Managed disks, the static public IP, and
every cache under /var/cache/webkit-dnd survive. Nothing is erased.

Authenticates with the automation account system assigned managed identity,
which holds Virtual Machine Contributor on the resource group.
#>

param(
    [Parameter(Mandatory = $false)]
    [object] $WebhookData
)

$ErrorActionPreference = 'Stop'

$ResourceGroup = 'rg-webkit-dnd'
$VmName        = 'azure-webkit-dnd-d16'

Write-Output "budget stop runbook starting at $(Get-Date -Format o)"

if ($WebhookData) {
    Write-Output "invoked by webhook"
    if ($WebhookData.RequestBody) {
        Write-Output "payload: $($WebhookData.RequestBody)"
    }
}
else {
    Write-Output "invoked without webhook data (manual or test run)"
}

try {
    Disable-AzContextAutosave -Scope Process | Out-Null
    $ctx = (Connect-AzAccount -Identity).context
    $ctx = Set-AzContext -SubscriptionName $ctx.Subscription -DefaultProfile $ctx
    Write-Output "authenticated as managed identity, subscription $($ctx.Subscription.Id)"
}
catch {
    Write-Error "managed identity sign in failed: $_"
    throw
}

$vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VmName -Status -DefaultProfile $ctx
$power = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus
Write-Output "current power state: $power"

if ($power -eq 'VM deallocated') {
    Write-Output "already deallocated, nothing to do"
    return
}

Write-Output "deallocating $VmName to stop compute billing"
Stop-AzVM -ResourceGroupName $ResourceGroup -Name $VmName -Force -DefaultProfile $ctx | Out-Null

$vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VmName -Status -DefaultProfile $ctx
$power = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus
Write-Output "final power state: $power"
Write-Output "disks, public IP, and caches are retained"
