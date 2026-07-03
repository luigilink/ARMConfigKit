# Requires: Azure CLI installed and logged in (az login)
# Scope: Update all managed disks (OS + data) on each VM in a resource group to StandardSSD_LRS

# =======================
# User parameters
# =======================
$resourceGroup = "RG-SPSE-SmallFarm" # <<< replace if needed
$targetSku     = "StandardSSD_LRS"   # other valid values: Standard_LRS, Premium_LRS, PremiumV2_LRS (region support applies)
$deallocateVM  = $true               # safer path for OS/data disk SKU changes
$whatIf        = $false              # dry-run first; set $false to execute changes
$startAfter    = $true               # start VM again if we deallocated it

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
    param(
        [string]$DiskId,
        [string]$NewSku,
        [switch]$WhatIf
    )
    if ($WhatIf) {
        Write-Host "  [WhatIf] Would run: az disk update --ids $DiskId --sku $NewSku" -ForegroundColor Yellow
        return $true
    }
    $null = az disk update --ids $DiskId --sku $NewSku --only-show-errors
    return $LASTEXITCODE -eq 0
}

function Get-VMDisks {
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
$vmList = az vm list -g $resourceGroup --output json | ConvertFrom-Json

if (-not $vmList -or $vmList.Count -eq 0) {
    Write-Host "No VMs found in resource group '$resourceGroup'." -ForegroundColor Yellow
    return
}

foreach ($vm in $vmList) {
    $vmName = $vm.name
    Write-Host "`n===== VM: $vmName =====" -ForegroundColor Cyan

    $vmDisks = Get-VMDisks -VmJson $vm

    # Collect all candidate disk IDs (OS + data), skipping nulls and ephemeral OS
    $diskIds = @()

    if ($vmDisks.EphemeralOs) {
        Write-Host "OS disk is Ephemeral for '$vmName' — skip OS disk SKU change." -ForegroundColor Yellow
    }
    else {
        if ($vmDisks.OsDiskId) { $diskIds += $vmDisks.OsDiskId }
        else { Write-Host "No managed OS disk ID detected on '$vmName'." -ForegroundColor Yellow }
    }

    if ($vmDisks.DataDiskIds -and $vmDisks.DataDiskIds.Count -gt 0) {
        $diskIds += $vmDisks.DataDiskIds
    }
    else {
        Write-Host "No managed data disks on '$vmName'." -ForegroundColor DarkGray
    }

    if ($diskIds.Count -eq 0) {
        Write-Host "Nothing to do for '$vmName'." -ForegroundColor DarkGray
        continue
    }

    # Identify which disks actually need changes
    $updates = @()
    foreach ($diskId in $diskIds) {
        $currentSku = Get-DiskSku -DiskId $diskId
        if (-not $currentSku) {
            Write-Host "  Could not read SKU for disk: $diskId — skipping." -ForegroundColor Yellow
            continue
        }

        if ($currentSku -eq "UltraSSD_LRS") {
            Write-Host "  Disk $diskId is UltraSSD — skipping (different semantics)." -ForegroundColor Yellow
            continue
        }

        if ($currentSku -ne $targetSku) {
            $updates += [pscustomobject]@{
                DiskId     = $diskId
                CurrentSku = $currentSku
                NewSku     = $targetSku
            }
        } else {
            Write-Host "  Disk $diskId already $targetSku" -ForegroundColor DarkGray
        }
    }

    if ($updates.Count -eq 0) {
        Write-Host "All disks on '$vmName' already at $targetSku." -ForegroundColor Green
        continue
    }

    # Deallocate (safer for OS and data disk SKU transitions)
    $wasDeallocated = $false
    if ($deallocateVM) {
        if ($whatIf) {
            Write-Host "[WhatIf] Would deallocate VM '$vmName' before updates." -ForegroundColor Yellow
            $wasDeallocated = $true
        } else {
            Write-Host "Deallocating VM '$vmName'..." -ForegroundColor Magenta
            az vm deallocate -g $resourceGroup -n $vmName --only-show-errors | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Failed to deallocate '$vmName'. Skipping this VM." -ForegroundColor Red
                continue
            }
            $wasDeallocated = $true
        }
    }

    # Apply disk SKU updates
    foreach ($item in $updates) {
        Write-Host ("Updating disk SKU: {0}`n    Current: {1}`n    Target : {2}" -f $item.DiskId, $item.CurrentSku, $item.NewSku) -ForegroundColor Cyan
        $ok = Set-DiskSku -DiskId $item.DiskId -NewSku $item.NewSku -WhatIf:$whatIf
        if (-not $ok) {
            Write-Host "  Update failed for $($item.DiskId)." -ForegroundColor Red
        }
    }

    # Start VM back if we deallocated it
    if ($wasDeallocated -and $startAfter) {
        if ($whatIf) {
            Write-Host "[WhatIf] Would start VM '$vmName' after updates." -ForegroundColor Yellow
        } else {
            Write-Host "Starting VM '$vmName'..." -ForegroundColor Magenta
            az vm start -g $resourceGroup -n $vmName --only-show-errors | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Failed to start VM '$vmName'. Please check the portal/CLI." -ForegroundColor Red
            }
        }
    }
}

Write-Host "`nDone." -ForegroundColor Green