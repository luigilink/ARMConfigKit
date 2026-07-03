#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.3.0' }

# Unit tests for the helper functions in scripts/StartAzVM.ps1.
# The script is dot-sourced so only its functions load (the remediation Main is
# guarded by an InvocationName check). These tests are cross-platform (pwsh 7 on
# macOS/Linux locally, windows-latest in CI) and never call the real az CLI.

BeforeAll {
    $script:ScriptPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'scripts/StartAzVM.ps1'
    . $script:ScriptPath
}

Describe 'Get-VMDisk' {
    It 'returns the OS disk id and the VM name' {
        $vm = [pscustomobject]@{
            name           = 'PDC1'
            storageProfile = [pscustomobject]@{
                osDisk    = [pscustomobject]@{ managedDisk = [pscustomobject]@{ id = '/disks/pdc1-os' } }
                dataDisks = @()
            }
        }
        $result = Get-VMDisk -VmJson $vm
        $result.VmName | Should -Be 'PDC1'
        $result.OsDiskId | Should -Be '/disks/pdc1-os'
        $result.EphemeralOs | Should -BeFalse
        @($result.DataDiskIds).Count | Should -Be 0
    }

    It 'collects all managed data disk ids' {
        $vm = [pscustomobject]@{
            name           = 'SQL1'
            storageProfile = [pscustomobject]@{
                osDisk    = [pscustomobject]@{ managedDisk = [pscustomobject]@{ id = '/disks/sql1-os' } }
                dataDisks = @(
                    [pscustomobject]@{ managedDisk = [pscustomobject]@{ id = '/disks/sql1-d0' } }
                    [pscustomobject]@{ managedDisk = [pscustomobject]@{ id = '/disks/sql1-d1' } }
                )
            }
        }
        $result = Get-VMDisk -VmJson $vm
        @($result.DataDiskIds) | Should -Be @('/disks/sql1-d0', '/disks/sql1-d1')
    }

    It 'flags an ephemeral OS disk (diffDiskSettings option = Local)' {
        $vm = [pscustomobject]@{
            name           = 'APP1'
            storageProfile = [pscustomobject]@{
                osDisk    = [pscustomobject]@{
                    managedDisk      = [pscustomobject]@{ id = '/disks/app1-os' }
                    diffDiskSettings = [pscustomobject]@{ option = 'Local' }
                }
                dataDisks = @()
            }
        }
        $result = Get-VMDisk -VmJson $vm
        $result.EphemeralOs | Should -BeTrue
    }

    It 'skips data disks that have no managed disk id' {
        $vm = [pscustomobject]@{
            name           = 'WFE1'
            storageProfile = [pscustomobject]@{
                osDisk    = [pscustomobject]@{ managedDisk = [pscustomobject]@{ id = '/disks/wfe1-os' } }
                dataDisks = @(
                    [pscustomobject]@{ managedDisk = [pscustomobject]@{ id = '/disks/wfe1-d0' } }
                    [pscustomobject]@{ managedDisk = $null }
                )
            }
        }
        $result = Get-VMDisk -VmJson $vm
        @($result.DataDiskIds) | Should -Be @('/disks/wfe1-d0')
    }
}

Describe 'Get-DiskSkuUpdatePlan' {
    It 'plans an update for a disk that is not at the target SKU' {
        $reader = { param($id) 'Standard_LRS' }
        $plan = Get-DiskSkuUpdatePlan -DiskId @('/d/1') -TargetSku 'StandardSSD_LRS' -SkuReader $reader
        @($plan.Updates).Count | Should -Be 1
        $plan.Updates[0].DiskId | Should -Be '/d/1'
        $plan.Updates[0].CurrentSku | Should -Be 'Standard_LRS'
        $plan.Updates[0].NewSku | Should -Be 'StandardSSD_LRS'
        @($plan.FailedReads).Count | Should -Be 0
    }

    It 'does not plan an update for a disk already at the target SKU' {
        $reader = { param($id) 'StandardSSD_LRS' }
        $plan = Get-DiskSkuUpdatePlan -DiskId @('/d/1') -TargetSku 'StandardSSD_LRS' -SkuReader $reader
        @($plan.Updates).Count | Should -Be 0
        @($plan.FailedReads).Count | Should -Be 0
    }

    It 'skips UltraSSD_LRS disks (different semantics)' {
        $reader = { param($id) 'UltraSSD_LRS' }
        $plan = Get-DiskSkuUpdatePlan -DiskId @('/d/ultra') -TargetSku 'StandardSSD_LRS' -SkuReader $reader
        @($plan.Updates).Count | Should -Be 0
        @($plan.FailedReads).Count | Should -Be 0
    }

    It 'reports disks whose SKU cannot be read' {
        $reader = { param($id) $null }
        $plan = Get-DiskSkuUpdatePlan -DiskId @('/d/x') -TargetSku 'StandardSSD_LRS' -SkuReader $reader
        @($plan.Updates).Count | Should -Be 0
        @($plan.FailedReads) | Should -Be @('/d/x')
    }

    It 'classifies a mixed set correctly' {
        $reader = {
            param($id)
            switch ($id) {
                '/d/toupdate' { 'Standard_LRS' }
                '/d/ok'       { 'StandardSSD_LRS' }
                '/d/ultra'    { 'UltraSSD_LRS' }
                '/d/unread'   { $null }
            }
        }
        $plan = Get-DiskSkuUpdatePlan -DiskId @('/d/toupdate', '/d/ok', '/d/ultra', '/d/unread') -TargetSku 'StandardSSD_LRS' -SkuReader $reader
        @($plan.Updates).DiskId | Should -Be @('/d/toupdate')
        @($plan.FailedReads) | Should -Be @('/d/unread')
    }
}

Describe 'Get-DiskSku' {
    It 'returns $null for an empty disk id without calling az' {
        Get-DiskSku -DiskId '' | Should -BeNullOrEmpty
    }

    It 'returns the trimmed SKU reported by az' {
        # Shadow the native `az` command with an in-scope function (functions take
        # precedence over external commands during name resolution).
        function az { "StandardSSD_LRS`n" }
        $global:LASTEXITCODE = 0
        Get-DiskSku -DiskId '/d/1' | Should -Be 'StandardSSD_LRS'
    }

    It 'returns $null when az reports an empty SKU' {
        function az { '' }
        $global:LASTEXITCODE = 0
        Get-DiskSku -DiskId '/d/1' | Should -BeNullOrEmpty
    }
}

Describe 'Set-DiskSku' {
    It 'does nothing and returns $true in WhatIf mode' {
        $script:azCalled = $false
        function az { $script:azCalled = $true }
        Set-DiskSku -DiskId '/d/1' -NewSku 'StandardSSD_LRS' -WhatIf | Should -BeTrue
        $script:azCalled | Should -BeFalse
    }

    It 'returns $true when az succeeds' {
        function az { $global:LASTEXITCODE = 0 }
        Set-DiskSku -DiskId '/d/1' -NewSku 'StandardSSD_LRS' | Should -BeTrue
    }

    It 'returns $false when az fails' {
        function az { $global:LASTEXITCODE = 1 }
        Set-DiskSku -DiskId '/d/1' -NewSku 'StandardSSD_LRS' | Should -BeFalse
    }
}
