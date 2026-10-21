#Requires -Version 7.0

<#
.SYNOPSIS
  Re-applies a target managed-disk SKU to every VM disk in a resource group.

.DESCRIPTION
  An Azure policy can periodically downgrade the lab's managed disks back to Standard HDD. For
  every VM in the resource group, this script deallocates the machine, runs `az disk update` on
  the OS and data disks that are not already at the target SKU, then starts the VM again. VMs are
  processed in parallel (ForEach-Object -Parallel, PowerShell 7+).

  Requires the Azure CLI, logged in (`az login`). Use the native -WhatIf switch to preview every
  change (disk updates, deallocate and start) without applying anything.

.PARAMETER ResourceGroup
  Resource group whose VMs are processed.

.PARAMETER TargetSku
  Disk SKU to apply (region support applies for Premium_LRS / PremiumV2_LRS).

.PARAMETER DeallocateVM
  Deallocate the VM before changing disk SKUs (the safer path for OS/data disk SKU changes).
  Use -DeallocateVM:$false to skip.

.PARAMETER StartAfter
  Start the VM again if the script deallocated it. Use -StartAfter:$false to leave it stopped.

.PARAMETER StartAll
  Start every VM of the resource group that is stopped (deallocated or stopped), even when none of
  its disks needed a SKU change. A VM the script deallocated itself stays governed by -StartAfter.
  Use -StartAll:$false to only restart the VMs whose disks were changed.

.PARAMETER ThrottleLimit
  Maximum number of VMs processed concurrently.

.EXAMPLE
  ./StartAzVM.ps1

.EXAMPLE
  ./StartAzVM.ps1 -WhatIf

.EXAMPLE
  ./StartAzVM.ps1 -ResourceGroup MyLab -TargetSku Premium_LRS
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ResourceGroup = 'ARMConfigKit',

    [ValidateSet('Standard_LRS', 'StandardSSD_LRS', 'Premium_LRS', 'PremiumV2_LRS')]
    [string]$TargetSku = 'StandardSSD_LRS',

    [bool]$DeallocateVM = $true,

    [bool]$StartAfter = $true,

    [bool]$StartAll = $true,

    [ValidateRange(1, 32)]
    [int]$ThrottleLimit = 5
)

# =======================
# Helpers
# =======================
function Get-DiskSku {
    param([string]$DiskId)
    if (-not $DiskId) { return $null }
    try {
        $sku = az disk show --ids $DiskId --query "sku.name" --output tsv 2>$null
        if ([string]::IsNullOrWhiteSpace($sku)) { return $null }
        return $sku.Trim()
    }
    catch {
        return $null
    }
}

function Set-DiskSku {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [string]$DiskId,
        [string]$NewSku
    )
    if (-not $PSCmdlet.ShouldProcess($DiskId, "Update disk SKU to $NewSku")) {
        return $true
    }
    $null = az disk update --ids $DiskId --sku $NewSku --only-show-errors
    return $LASTEXITCODE -eq 0
}

function Invoke-VMDeallocate {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )
    if (-not $PSCmdlet.ShouldProcess($VmName, 'Deallocate VM')) {
        return $true
    }
    $null = az vm deallocate -g $ResourceGroup -n $VmName --only-show-errors
    return $LASTEXITCODE -eq 0
}

function Invoke-VMStart {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )
    if (-not $PSCmdlet.ShouldProcess($VmName, 'Start VM')) {
        return $true
    }
    $null = az vm start -g $ResourceGroup -n $VmName --only-show-errors
    return $LASTEXITCODE -eq 0
}

function Test-VMStartRequired {
    <#
      Pure decision: should a VM with this power state (as reported by `az vm list -d`, e.g.
      "VM deallocated") be started? Only fully stopped VMs qualify; running VMs and transitional
      states (starting / stopping / deallocating) are left alone, and so is an unknown state.
    #>
    [OutputType([bool])]
    param([string]$PowerState)
    return $PowerState -in @('VM deallocated', 'VM stopped')
}

function Invoke-VMStartIfStopped {
    <#
      Starts the VM when its reported power state says it is stopped. Returns
      @{ Action = 'Started' | 'Skipped'; Failed = $true/$false }. -WhatIf is honoured through
      Invoke-VMStart (preference variables flow down the call stack).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $VmJson,
        [string]$ResourceGroup
    )
    if (-not (Test-VMStartRequired -PowerState $VmJson.powerState)) {
        return [pscustomobject]@{ Action = 'Skipped'; Failed = $false }
    }
    $ok = Invoke-VMStart -ResourceGroup $ResourceGroup -VmName $VmJson.name
    return [pscustomobject]@{ Action = 'Started'; Failed = (-not $ok) }
}

function Get-VMDisk {
    <#
      Returns an object:
      @{
        VmName   = <name>
        OsDiskId = <id or $null>
        DataDiskIds = @(<ids>)
        EphemeralOs = $true/$false
      }
    #>
    param($VmJson)

    $sp = $VmJson.storageProfile
    $osDiskId   = $sp.osDisk.managedDisk.id
    $ephemeral  = $false
    if ($sp.osDisk.diffDiskSettings -and $sp.osDisk.diffDiskSettings.option) {
        # Ephemeral OS Disk if option == "Local"
        $ephemeral = ($sp.osDisk.diffDiskSettings.option -eq "Local")
    }
    $dataDiskIds = @()
    if ($sp.dataDisks) {
        foreach ($dd in $sp.dataDisks) {
            if ($dd.managedDisk -and $dd.managedDisk.id) {
                $dataDiskIds += $dd.managedDisk.id
            }
        }
    }
    return [pscustomobject]@{
        VmName      = $VmJson.name
        OsDiskId    = $osDiskId
        DataDiskIds = $dataDiskIds
        EphemeralOs = $ephemeral
    }
}

function Get-DiskSkuUpdatePlan {
    <#
      Decide, for a set of disk IDs, which ones need their SKU changed to the
      target. Pure decision function (the SKU lookup is injected) so it can be
      unit-tested without calling Azure.

      Returns an object:
      @{
        Updates     = @( @{ DiskId; CurrentSku; NewSku } ... )  # disks to change
        FailedReads = @( <diskId> ... )                         # SKU unreadable
      }
    #>
    param(
        [string[]]$DiskId,
        [string]$TargetSku,
        # Function that returns the current SKU for a disk id (injected so tests
        # can supply a stub instead of calling az).
        [scriptblock]$SkuReader = { param($id) Get-DiskSku -DiskId $id }
    )

    $updates = @()
    $failedReads = @()
    foreach ($id in $DiskId) {
        $currentSku = & $SkuReader $id
        if (-not $currentSku) {
            $failedReads += $id
            continue
        }
        if ($currentSku -eq "UltraSSD_LRS") {
            continue
        }
        if ($currentSku -ne $TargetSku) {
            $updates += [pscustomobject]@{
                DiskId     = $id
                CurrentSku = $currentSku
                NewSku     = $TargetSku
            }
        }
    }

    return [pscustomobject]@{
        Updates     = $updates
        FailedReads = $failedReads
    }
}

# =======================
# Main
# =======================
# When the script is dot-sourced (e.g. by the Pester tests) only the functions
# above are loaded; the remediation below must not run.
if ($MyInvocation.InvocationName -eq '.') { return }

Write-Host "Listing VMs in resource group '$ResourceGroup'..." -ForegroundColor Cyan

# -d (show details) adds each VM's powerState, needed by -StartAll.
# Capture raw output and validate the az call before parsing: a non-zero exit
# code (expired login, wrong/empty resource group, missing permissions) must be
# surfaced as an error, not silently masked as "no VMs". Invalid/partial JSON
# would otherwise make ConvertFrom-Json throw an unhandled terminating error.
$vmListRaw = az vm list -g $ResourceGroup -d --output json 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to list VMs in resource group '$ResourceGroup' (az exit code $LASTEXITCODE). Check 'az login', the resource group name and your permissions." -ForegroundColor Red
    exit 1
}

try {
    $vmList = ($vmListRaw -join "`n") | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Host "Failed to parse the VM list returned by az: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not $vmList -or $vmList.Count -eq 0) {
    Write-Host "No VMs found in resource group '$ResourceGroup'." -ForegroundColor Yellow
    return
}

# Capture the helper definitions once so they can be re-created inside each
# parallel runspace — functions from the parent scope are NOT inherited by
# ForEach-Object -Parallel. This keeps a single source of truth (the functions
# defined above) rather than duplicating their bodies.
$getDiskSkuDef  = ${function:Get-DiskSku}.ToString()
$setDiskSkuDef  = ${function:Set-DiskSku}.ToString()
$deallocateDef  = ${function:Invoke-VMDeallocate}.ToString()
$startDef       = ${function:Invoke-VMStart}.ToString()
$needStartDef   = ${function:Test-VMStartRequired}.ToString()
$startIfDef     = ${function:Invoke-VMStartIfStopped}.ToString()
$getVMDisksDef  = ${function:Get-VMDisk}.ToString()
$getPlanDef     = ${function:Get-DiskSkuUpdatePlan}.ToString()

# Native -WhatIf: $WhatIfPreference is not inherited by the parallel runspaces, so capture it
# here and forward it explicitly to every ShouldProcess-aware helper. ShouldProcess also does not
# print its "What if:" message from a parallel runspace, so each step announces itself with an
# explicit prefix below to make a simulation unambiguous.
$dryRun = [bool]$WhatIfPreference
if ($dryRun) {
    Write-Host "WhatIf: simulation only — no VM will be deallocated or started and no disk will be changed." -ForegroundColor Yellow
}

$results = $vmList | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
    # ---- Re-hydrate the parent scope -------------------------------------
    # Variables from the parent scope are not visible here, so bring across
    # everything this block needs via $using:.
    $resourceGroup = $using:ResourceGroup
    $targetSku     = $using:TargetSku
    $deallocateVM  = $using:DeallocateVM
    $whatIf        = $using:dryRun
    $startAfter    = $using:StartAfter
    $startAll      = $using:StartAll

    # Re-create the helper functions inside this runspace from the captured
    # definitions.
    ${function:Get-DiskSku} = $using:getDiskSkuDef
    ${function:Set-DiskSku} = $using:setDiskSkuDef
    ${function:Invoke-VMDeallocate} = $using:deallocateDef
    ${function:Invoke-VMStart} = $using:startDef
    ${function:Test-VMStartRequired} = $using:needStartDef
    ${function:Invoke-VMStartIfStopped} = $using:startIfDef
    ${function:Get-VMDisk} = $using:getVMDisksDef
    ${function:Get-DiskSkuUpdatePlan} = $using:getPlanDef

    $vm     = $_
    $vmName = $vm.name

    # Per-VM result object emitted to the pipeline so the caller can report a
    # summary and set a meaningful exit code. Every code path below returns this.
    $result = [pscustomobject]@{
        VmName           = $vmName
        Updated          = 0
        Failed           = 0
        DeallocateFailed = $false
        StillDeallocated = $false
        Started          = $false
    }

    # -StartAll step, used on every path where the script has not changed the VM's power state
    # itself: starts the VM when it is stopped and records the outcome in the result.
    $startIfStopped = {
        if (-not $startAll) { return }
        try {
            $r = Invoke-VMStartIfStopped -VmJson $vm -ResourceGroup $resourceGroup -WhatIf:$whatIf -ErrorAction Stop
        }
        catch {
            Write-Host "[$vmName] -StartAll failed: $($_.Exception.Message)" -ForegroundColor Red
            $result.Failed++
            return
        }
        if ($r.Action -eq 'Started') {
            $prefix = if ($whatIf) { 'What if: would start stopped VM' } else { 'Starting stopped VM' }
            Write-Host "[$vmName] $prefix ($($vm.powerState))." -ForegroundColor Magenta
            if ($r.Failed) {
                Write-Host "[$vmName] Failed to start VM. Please check the portal/CLI." -ForegroundColor Red
                $result.StillDeallocated = $true
                $result.Failed++
            }
            else { $result.Started = $true }
        }
    }

    Write-Host "`n===== VM: $vmName =====" -ForegroundColor Cyan

    $vmDisks = Get-VMDisk -VmJson $vm

    # Collect all candidate disk IDs (OS + data), skipping nulls and ephemeral OS
    $diskIds = @()

    if ($vmDisks.EphemeralOs) {
        Write-Host "[$vmName] OS disk is Ephemeral — skip OS disk SKU change." -ForegroundColor Yellow
    }
    else {
        if ($vmDisks.OsDiskId) { $diskIds += $vmDisks.OsDiskId }
        else { Write-Host "[$vmName] No managed OS disk ID detected." -ForegroundColor Yellow }
    }

    if ($vmDisks.DataDiskIds -and $vmDisks.DataDiskIds.Count -gt 0) {
        $diskIds += $vmDisks.DataDiskIds
    }
    else {
        Write-Host "[$vmName] No managed data disks." -ForegroundColor DarkGray
    }

    if ($diskIds.Count -eq 0) {
        Write-Host "[$vmName] Nothing to do." -ForegroundColor DarkGray
        & $startIfStopped
        return $result
    }

    # Identify which disks actually need changes (pure decision, unit-tested)
    $plan = Get-DiskSkuUpdatePlan -DiskId $diskIds -TargetSku $targetSku
    $updates = @($plan.Updates)

    foreach ($failedId in $plan.FailedReads) {
        Write-Host "[$vmName]   Could not read SKU for disk: $failedId — skipping." -ForegroundColor Yellow
        $result.Failed++
    }

    if ($updates.Count -eq 0) {
        if ($result.Failed -eq 0) {
            Write-Host "[$vmName] All disks already at $targetSku (or skipped)." -ForegroundColor Green
        }
        & $startIfStopped
        return $result
    }

    # Deallocate (safer for OS and data disk SKU transitions)
    $wasDeallocated = $false
    if ($deallocateVM) {
        $prefix = if ($whatIf) { 'What if: would deallocate VM' } else { 'Deallocating VM' }
        Write-Host "[$vmName] $prefix..." -ForegroundColor Magenta
        if (-not (Invoke-VMDeallocate -ResourceGroup $resourceGroup -VmName $vmName -WhatIf:$whatIf)) {
            Write-Host "[$vmName] Failed to deallocate. Skipping this VM." -ForegroundColor Red
            $result.DeallocateFailed = $true
            $result.Failed++
            return $result
        }
        $wasDeallocated = $true
    }

    # Apply disk SKU updates
    foreach ($item in $updates) {
        $prefix = if ($whatIf) { 'What if: would update disk SKU' } else { 'Updating disk SKU' }
        Write-Host ("[$vmName] {3}: {0}`n    Current: {1}`n    Target : {2}" -f $item.DiskId, $item.CurrentSku, $item.NewSku, $prefix) -ForegroundColor Cyan
        $ok = Set-DiskSku -DiskId $item.DiskId -NewSku $item.NewSku -WhatIf:$whatIf
        if ($ok) {
            $result.Updated++
        } else {
            Write-Host "[$vmName]   Update failed for $($item.DiskId)." -ForegroundColor Red
            $result.Failed++
        }
    }

    # Start VM back if we deallocated it
    if ($wasDeallocated -and $startAfter) {
        $prefix = if ($whatIf) { 'What if: would start VM' } else { 'Starting VM' }
        Write-Host "[$vmName] $prefix..." -ForegroundColor Magenta
        if (-not (Invoke-VMStart -ResourceGroup $resourceGroup -VmName $vmName -WhatIf:$whatIf)) {
            Write-Host "[$vmName] Failed to start VM. Please check the portal/CLI." -ForegroundColor Red
            $result.StillDeallocated = $true
            $result.Failed++
        }
        else { $result.Started = $true }
    }

    # The script left the VM's power state untouched (disks changed without a deallocate), so
    # apply -StartAll. A VM the script deallocated stays governed by -StartAfter above.
    if (-not $wasDeallocated) { & $startIfStopped }

    return $result
}

# =======================
# Summary
# =======================
Write-Host "`n===== Summary =====" -ForegroundColor Cyan
$results |
    Sort-Object VmName |
    Format-Table VmName, Updated, Started, Failed, DeallocateFailed, StillDeallocated -AutoSize |
    Out-Host

$failedVms = @($results | Where-Object { $_.Failed -gt 0 -or $_.StillDeallocated -or $_.DeallocateFailed })
if ($failedVms.Count -gt 0) {
    $names = ($failedVms | ForEach-Object { $_.VmName }) -join ", "
    Write-Host "Completed with errors on: $names" -ForegroundColor Red
    $stuck = @($results | Where-Object { $_.StillDeallocated })
    if ($stuck.Count -gt 0) {
        $stuckNames = ($stuck | ForEach-Object { $_.VmName }) -join ", "
        Write-Host "WARNING: the following VMs were deallocated but could not be started again: $stuckNames" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Done." -ForegroundColor Green
