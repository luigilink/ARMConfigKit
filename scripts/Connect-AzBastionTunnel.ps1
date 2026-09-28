<#
.SYNOPSIS
  Opens one or more Azure Bastion native-client tunnels (RDP/SSH over 443) so a
  local RDP client (Windows App on macOS, mstsc on Windows) can reach lab VMs
  without the heavy browser Bastion experience.

.DESCRIPTION
  For each requested VM the script resolves its resource ID and starts an
  `az network bastion tunnel` on an incrementing local loopback port, then prints
  the VM -> localhost:port mapping. All tunnels run until you press Enter (or
  Ctrl+C), at which point every tunnel process is stopped.

  Requires the Bastion host to be Standard SKU with Native Client Support
  (tunneling) enabled — Basic SKU only supports the browser connection.

.PARAMETER ResourceGroup
  Resource group holding the Bastion host and the target VMs. Default 'ARMConfigKit'.

.PARAMETER BastionName
  Name of the Bastion host. Default 'armconfigkit-BASTION'.

.PARAMETER VMName
  One or more VM names to tunnel to (e.g. PULL, APP1, APP2). Each gets its own
  local port.

.PARAMETER BasePort
  First local port to use; subsequent VMs use BasePort+1, BasePort+2, ... Default 50001.

.PARAMETER ResourcePort
  Port on the target VM to tunnel to. Default 3389 (RDP); use 22 for SSH.

.EXAMPLE
  .\Connect-AzBastionTunnel.ps1 -VMName APP1

.EXAMPLE
  .\Connect-AzBastionTunnel.ps1 -VMName PULL,APP1,APP2 -BasePort 50001
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ResourceGroup = 'ARMConfigKit',
    [string]$BastionName = 'armconfigkit-BASTION',
    [Parameter(Mandatory)]
    [string[]]$VMName,
    [int]$BasePort = 50001,
    [int]$ResourcePort = 3389
)

# Resolve the az executable once (az.cmd on Windows, a shim on macOS/Linux) so
# Start-Process gets a concrete path rather than relying on PATH resolution.
$azCommand = Get-Command az -ErrorAction SilentlyContinue
if (-not $azCommand) {
    Write-Host "Azure CLI ('az') not found on PATH. Install it and run 'az login'." -ForegroundColor Red
    exit 1
}
$azCmd = $azCommand.Source

# A free loopback port can be bound momentarily; used to avoid colliding with an
# already-open tunnel or another local listener.
function Test-LocalPortFree {
    param([int]$Port)
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start(); $listener.Stop(); return $true
    }
    catch { return $false }
}

# =======================
# Preflight
# =======================
az account show --query id -o tsv 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Not logged in to Azure CLI. Run 'az login' first." -ForegroundColor Red
    exit 1
}

# Tunneling only exists on Standard SKU; fail fast with an actionable message
# instead of letting each 'az network bastion tunnel' error out obscurely.
$bastion = az network bastion show --name $BastionName --resource-group $ResourceGroup `
    --query "{sku:sku.name, tunneling:enableTunneling}" -o json 2>$null | ConvertFrom-Json
if (-not $bastion) {
    Write-Host "Bastion '$BastionName' not found in resource group '$ResourceGroup'." -ForegroundColor Red
    exit 1
}
if ($bastion.sku -ne 'Standard' -or -not $bastion.tunneling) {
    Write-Host ("Bastion '{0}' is SKU '{1}' (tunneling={2}). Native client tunnels need Standard SKU with tunneling enabled:" -f $BastionName, $bastion.sku, $bastion.tunneling) -ForegroundColor Red
    Write-Host "  az network bastion update --name $BastionName --resource-group $ResourceGroup --sku name=Standard --enable-tunneling true" -ForegroundColor Yellow
    exit 1
}

# =======================
# Open the tunnels
# =======================
$tunnels = @()
$port = $BasePort
$tmp = [System.IO.Path]::GetTempPath()

try {
    foreach ($vm in $VMName) {
        $resourceId = az vm show --resource-group $ResourceGroup --name $vm --query id -o tsv 2>$null
        if ([string]::IsNullOrWhiteSpace($resourceId)) {
            Write-Host "[$vm] VM not found in resource group '$ResourceGroup' — skipping." -ForegroundColor Yellow
            continue
        }

        while (-not (Test-LocalPortFree -Port $port)) {
            Write-Host "Local port $port is busy, trying $($port + 1)..." -ForegroundColor DarkGray
            $port++
        }

        $outLog = Join-Path $tmp "bastion-$vm-$port.out.log"
        $errLog = Join-Path $tmp "bastion-$vm-$port.err.log"
        $azArgs = @(
            'network', 'bastion', 'tunnel',
            '--name', $BastionName,
            '--resource-group', $ResourceGroup,
            '--target-resource-id', $resourceId,
            '--resource-port', $ResourcePort,
            '--port', $port
        )

        Write-Host "[$vm] Opening tunnel -> localhost:$port (VM port $ResourcePort)..." -ForegroundColor Cyan
        $proc = Start-Process -FilePath $azCmd -ArgumentList $azArgs -PassThru -NoNewWindow `
            -RedirectStandardOutput $outLog -RedirectStandardError $errLog

        # The tunnel is ready once the local port starts listening; poll briefly.
        $ready = $false
        foreach ($i in 1..20) {
            Start-Sleep -Milliseconds 500
            if ($proc.HasExited) { break }
            if (-not (Test-LocalPortFree -Port $port)) { $ready = $true; break }
        }

        if ($proc.HasExited) {
            Write-Host "[$vm] Tunnel process exited early. See $errLog" -ForegroundColor Red
            continue
        }
        if (-not $ready) {
            Write-Host "[$vm] Port $port not listening yet; the tunnel may still be starting." -ForegroundColor Yellow
        }

        $tunnels += [pscustomobject]@{ VM = $vm; Port = $port; Process = $proc; OutLog = $outLog; ErrLog = $errLog }
        $port++
    }

    if ($tunnels.Count -eq 0) {
        Write-Host "No tunnels were opened." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "`n===== Active tunnels =====" -ForegroundColor Green
    $tunnels | Format-Table VM, @{ N = 'Connect to'; E = { "localhost:$($_.Port)" } } -AutoSize | Out-Host
    $hint = if ($ResourcePort -eq 3389) { "Windows App (macOS) / mstsc (Windows): add a PC 'localhost:<port>'." }
    else { "SSH: ssh <user>@localhost -p <port>" }
    Write-Host $hint -ForegroundColor Cyan
    Write-Host "Press Enter to close all tunnels..." -ForegroundColor DarkGray
    [void](Read-Host)
}
finally {
    # Always tear down every tunnel we started, even on Ctrl+C.
    foreach ($t in $tunnels) {
        if ($t.Process -and -not $t.Process.HasExited) {
            Write-Host "[$($t.VM)] Closing tunnel on localhost:$($t.Port)..." -ForegroundColor Magenta
            Stop-Process -Id $t.Process.Id -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -Path $t.OutLog, $t.ErrLog -ErrorAction SilentlyContinue
    }
    Write-Host "Done." -ForegroundColor Green
}
