<#
.SYNOPSIS
  Opens one or more Azure Bastion native-client tunnels (RDP/SSH over 443) so a
  local RDP client (Windows App on macOS, mstsc on Windows) can reach lab VMs
  without the heavy browser Bastion experience.

.DESCRIPTION
  Tunnels are described either by a config file (-ConfigPath, a .psd1 listing the
  VMs and their local ports) or inline with -VMName. For each VM the script
  resolves its resource ID and starts an `az network bastion tunnel` on a local
  loopback port, then prints the VM -> localhost:port mapping. All tunnels run
  until you press Enter (or Ctrl+C), at which point every tunnel is stopped.

  A config file gives each VM a STABLE port, so the matching PCs in Windows App
  can be configured once and reused. Copy BastionTunnels.psd1.example to
  BastionTunnels.psd1 (git-ignored) and adjust it.

  Requires the Bastion host to be Standard SKU with Native Client Support
  (tunneling) enabled — Basic SKU only supports the browser connection.

.PARAMETER ConfigPath
  Path to a .psd1 config file. Defaults to BastionTunnels.psd1 next to this
  script when it exists. The file supplies ResourceGroup, BastionName,
  ResourcePort and a VMs list (each entry: Name, optional Port).

.PARAMETER VMName
  One or more VM names to tunnel to. Overrides the config VM list when supplied;
  ports are then assigned incrementally from -BasePort.

.PARAMETER ResourceGroup
  Resource group holding the Bastion host and the VMs. Overrides the config value.

.PARAMETER BastionName
  Name of the Bastion host. Overrides the config value.

.PARAMETER BasePort
  First local port for VMs without an explicit port (incremented per VM). Default 50001.

.PARAMETER ResourcePort
  Port on the target VM to tunnel to. Default 3389 (RDP); use 22 for SSH.

.EXAMPLE
  .\Connect-AzBastionTunnel.ps1 -ConfigPath .\BastionTunnels.psd1

.EXAMPLE
  .\Connect-AzBastionTunnel.ps1 -VMName APP1,APP2 -BasePort 50004
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string[]]$VMName,
    [string]$ResourceGroup,
    [string]$BastionName,
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
# Resolve configuration (explicit params override the config file)
# =======================
$config = $null
if (-not $PSBoundParameters.ContainsKey('ConfigPath')) {
    $default = Join-Path $PSScriptRoot 'BastionTunnels.psd1'
    if (Test-Path $default) { $ConfigPath = $default }
}
if ($ConfigPath) {
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "Config file not found: $ConfigPath" -ForegroundColor Red
        exit 1
    }
    $config = Import-PowerShellDataFile -Path $ConfigPath
}

if (-not $ResourceGroup) { $ResourceGroup = $config.ResourceGroup }
if (-not $BastionName) { $BastionName = $config.BastionName }
if (-not $PSBoundParameters.ContainsKey('ResourcePort') -and $config.ResourcePort) { $ResourcePort = $config.ResourcePort }
if ([string]::IsNullOrWhiteSpace($ResourceGroup)) { $ResourceGroup = 'ARMConfigKit' }
if ([string]::IsNullOrWhiteSpace($BastionName)) { $BastionName = 'armconfigkit-BASTION' }

# Build the list of tunnels: { Name; Port } — inline -VMName wins, else the
# config VMs (with their explicit ports), else nothing.
$requested = @()
$autoPort = $BasePort
if ($VMName) {
    foreach ($name in $VMName) { $requested += [pscustomobject]@{ Name = $name; Port = $autoPort }; $autoPort++ }
}
elseif ($config -and $config.VMs) {
    foreach ($vm in $config.VMs) {
        $p = if ($vm.Port) { [int]$vm.Port } else { $autoPort; $autoPort++ }
        $requested += [pscustomobject]@{ Name = $vm.Name; Port = $p }
    }
}
if ($requested.Count -eq 0) {
    Write-Host "No VMs to tunnel. Pass -VMName or provide a config file with a VMs list." -ForegroundColor Red
    exit 1
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
$tmp = [System.IO.Path]::GetTempPath()

try {
    foreach ($entry in $requested) {
        $vm = $entry.Name
        $port = $entry.Port

        $resourceId = az vm show --resource-group $ResourceGroup --name $vm --query id -o tsv 2>$null
        if ([string]::IsNullOrWhiteSpace($resourceId)) {
            Write-Host "[$vm] VM not found in resource group '$ResourceGroup' — skipping." -ForegroundColor Yellow
            continue
        }

        while (-not (Test-LocalPortFree -Port $port)) {
            Write-Host "[$vm] Local port $port is busy, trying $($port + 1)..." -ForegroundColor DarkGray
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
