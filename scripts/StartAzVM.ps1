# Requires: Azure CLI installed and logged in (az login)
# Requires: PowerShell 7+ (uses ForEach-Object -Parallel)
# Scope: Update all managed disks (OS + data) on each VM in a resource group to StandardSSD_LRS
#        The VMs are processed in parallel to speed up a full remediation pass.
#Requires -Version 7.0

# =======================
# User parameters
# =======================
$resourceGroup = "RG-SPSE-SmallFarm" # <<< replace if needed
$targetSku     = "StandardSSD_LRS"   # other valid values: Standard_LRS, Premium_LRS, PremiumV2_LRS (region support applies)
$deallocateVM  = $true               # safer path for OS/data disk SKU changes
$whatIf        = $true               # dry-run by default; set to $false to execute changes
$startAfter    = $true               # start VM again if we deallocated it
$throttleLimit = 5                   # max number of VMs processed concurrently

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

# =======================
# Main
# =======================
Write-Host "Listing VMs in resource group '$resourceGroup'..." -ForegroundColor Cyan

# Capture raw output and validate the az call before parsing: a non-zero exit
# code (expired login, wrong/empty resource group, missing permissions) must be
# surfaced as an error, not silently masked as "no VMs". Invalid/partial JSON
# would otherwise make ConvertFrom-Json throw an unhandled terminating error.
$vmListRaw = az vm list -g $resourceGroup --output json 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to list VMs in resource group '$resourceGroup' (az exit code $LASTEXITCODE). Check 'az login', the resource group name and your permissions." -ForegroundColor Red
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
    Write-Host "No VMs found in resource group '$resourceGroup'." -ForegroundColor Yellow
    return
}

# Capture the helper definitions once so they can be re-created inside each
# parallel runspace — functions from the parent scope are NOT inherited by
# ForEach-Object -Parallel. This keeps a single source of truth (the functions
# defined above) rather than duplicating their bodies.
$getDiskSkuDef = ${function:Get-DiskSku}.ToString()
$setDiskSkuDef = ${function:Set-DiskSku}.ToString()
$getVMDisksDef = ${function:Get-VMDisk}.ToString()

$results = $vmList | ForEach-Object -ThrottleLimit $throttleLimit -Parallel {
    # ---- Re-hydrate the parent scope -------------------------------------
    # Variables from the parent scope are not visible here, so bring across
    # everything this block needs via $using:.
    $resourceGroup = $using:resourceGroup
    $targetSku     = $using:targetSku
    $deallocateVM  = $using:deallocateVM
    $whatIf        = $using:whatIf
    $startAfter    = $using:startAfter

    # Re-create the helper functions inside this runspace from the captured
    # definitions.
    ${function:Get-DiskSku} = $using:getDiskSkuDef
    ${function:Set-DiskSku} = $using:setDiskSkuDef
    ${function:Get-VMDisk} = $using:getVMDisksDef

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
        return $result
    }

    # Identify which disks actually need changes
    $updates = @()
    foreach ($diskId in $diskIds) {
        $currentSku = Get-DiskSku -DiskId $diskId
        if (-not $currentSku) {
            Write-Host "[$vmName]   Could not read SKU for disk: $diskId — skipping." -ForegroundColor Yellow
            $result.Failed++
            continue
        }

        if ($currentSku -eq "UltraSSD_LRS") {
            Write-Host "[$vmName]   Disk $diskId is UltraSSD — skipping (different semantics)." -ForegroundColor Yellow
            continue
        }

        if ($currentSku -ne $targetSku) {
            $updates += [pscustomobject]@{
                DiskId     = $diskId
                CurrentSku = $currentSku
                NewSku     = $targetSku
            }
        } else {
            Write-Host "[$vmName]   Disk $diskId already $targetSku" -ForegroundColor DarkGray
        }
    }

    if ($updates.Count -eq 0) {
        if ($result.Failed -eq 0) {
            Write-Host "[$vmName] All disks already at $targetSku." -ForegroundColor Green
        }
        return $result
    }

    # Deallocate (safer for OS and data disk SKU transitions)
    $wasDeallocated = $false
    if ($deallocateVM) {
        if ($whatIf) {
            Write-Host "[$vmName] [WhatIf] Would deallocate VM before updates." -ForegroundColor Yellow
            $wasDeallocated = $true
        } else {
            Write-Host "[$vmName] Deallocating VM..." -ForegroundColor Magenta
            az vm deallocate -g $resourceGroup -n $vmName --only-show-errors | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[$vmName] Failed to deallocate. Skipping this VM." -ForegroundColor Red
                $result.DeallocateFailed = $true
                $result.Failed++
                return $result
            }
            $wasDeallocated = $true
        }
    }

    # Apply disk SKU updates
    foreach ($item in $updates) {
        Write-Host ("[$vmName] Updating disk SKU: {0}`n    Current: {1}`n    Target : {2}" -f $item.DiskId, $item.CurrentSku, $item.NewSku) -ForegroundColor Cyan
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
        if ($whatIf) {
            Write-Host "[$vmName] [WhatIf] Would start VM after updates." -ForegroundColor Yellow
        } else {
            Write-Host "[$vmName] Starting VM..." -ForegroundColor Magenta
            az vm start -g $resourceGroup -n $vmName --only-show-errors | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[$vmName] Failed to start VM. Please check the portal/CLI." -ForegroundColor Red
                $result.StillDeallocated = $true
                $result.Failed++
            }
        }
    }

    return $result
}

# =======================
# Summary
# =======================
Write-Host "`n===== Summary =====" -ForegroundColor Cyan
$results |
    Sort-Object VmName |
    Format-Table VmName, Updated, Failed, DeallocateFailed, StillDeallocated -AutoSize |
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
