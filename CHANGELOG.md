# Change log for ARMConfigKit

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `StartAzVM.ps1 -StartAll` starts every stopped VM, not only the ones whose disks were fixed (#40)
  - The script used to start a VM only when it had deallocated it itself, i.e. when at least one
    of its disks needed a SKU change, so a VM stopped by the nightly auto-shutdown stayed stopped
    whenever its disks were already at the target SKU. The new `-StartAll` parameter (default
    `$true`) starts every VM of the resource group whose power state is `VM deallocated` or
    `VM stopped`; running VMs and transitional states are left alone. The VM list is now read with
    `az vm list -d` to get the power state, the summary gains a `Started` column, `-WhatIf` issues
    no start, and a failed start is reported and sets exit code 1. A VM the script deallocated
    itself remains governed by `-StartAfter`. Use `-StartAll:$false` for the previous behaviour.

### Changed

- `StartAzVM.ps1` now takes parameters and uses the native `-WhatIf` (#38)
  - The top-of-file variables (`$resourceGroup`, `$targetSku`, `$deallocateVM`, `$startAfter`,
    `$throttleLimit`) are replaced by a `param()` block (`-ResourceGroup`, `-TargetSku` validated
    against the supported disk SKUs, `-DeallocateVM`, `-StartAfter`, `-ThrottleLimit`) whose
    defaults are the previous values, so the script can be run every day without editing a tracked
    file. The hand-rolled `$whatIf` flag is replaced by the standard `-WhatIf` switch, which now
    also covers the deallocate and start steps (through new `Invoke-VMDeallocate` /
    `Invoke-VMStart` helpers) and is propagated into the parallel runspaces. **Behaviour change:**
    the script no longer defaults to a dry run — pass `-WhatIf` to simulate. `-Confirm` is not
    supported because VMs are processed in parallel.

- Document overriding the VM topology in `terraform.tfvars` instead of editing `variables.tf` (#36)
  - `vms_informations` is the only variable that is specific to a given lab, yet it lived as the
    `default` in the tracked `variables.tf`, so a local topology left that file permanently modified.
    `variables.tf` keeps a generic default, and `terraform.tfvars.example` now shows a commented
    `vms_informations` override for the git-ignored `terraform.tfvars`. The README, the Topology and
    Getting-Started wiki pages point there. A tfvars value replaces the whole map, so the override
    must list every VM. No infrastructure change: the variable keeps its name, type and default.

### Added

- Added `scripts/Connect-AzBastionTunnel.ps1` (#34)
  - Opens one or more native-client Azure Bastion tunnels (RDP/SSH over 443), one local
    loopback port per VM, so a local client (Windows App on macOS, mstsc on Windows) can reach
    the lab VMs without the bandwidth-heavy browser Bastion session. Can be driven by a `.psd1`
    config file (`-ConfigPath`, defaulting to `scripts/BastionTunnels.psd1`) that assigns each VM
    a stable local port, or inline with `-VMName`. A tracked `BastionTunnels.psd1.example`
    template ships the sample topology; the real `BastionTunnels.psd1` is git-ignored. Preflights
    `az login`, the Bastion Standard SKU + tunneling requirement (prints the upgrade command
    otherwise) and each VM's resource ID; handles busy local ports, waits for the port to listen,
    and tears every tunnel down on exit. Requires PowerShell 7+ and the Azure CLI.

## [1.1.0] - 2026-09-23

### Changed

- Bumped the AzureRM provider to `4.81.0` (#29)
  - `terraform/main.tf` now pins `azurerm = "=4.81.0"` (was `=4.80.0`). Refreshing the lock
    file with `terraform init -upgrade` also moved two transitive providers used by the AVM
    modules: `random` `3.9.0` → `3.9.1` and `tls` `4.3.0` → `4.4.1`. `azapi` stays pinned at
    `=2.7.0` (documented identity bug in 2.8.0).
- The default `resource_group_name` is now `ARMConfigKit` (was `RG-SPSE-SmallFarm`) (#21)
  - Updated the Terraform default (`terraform/variables.tf`), the commented example in
    `terraform/terraform.tfvars.example`, the `StartAzVM.ps1` sample resource group, and the
    variables table in `wiki/Configuration.md`. The derived resource prefix now defaults to
    `armconfigkit` (e.g. `armconfigkit-VNET`). The naming-derivation example in the wiki was
    refreshed to `Contoso-SPSE-Farm → contosospsef`, which still illustrates the
    lowercase/strip/truncate-to-12 rule on a messy name. Defaults and documentation only — no
    change to the deployment behaviour.
- Polished the README and wiki (#23)
  - Enriched the README badge row (latest release/version, license, CI Terraform and Pester
    status, last commit) and moved the full `Topology` table out of the README into a dedicated
    `Topology` wiki page, leaving a short intro and link behind. Added a `_Sidebar.md` wiki
    navigation (mirroring the other luigilink kits) and refreshed the `Home` page list.
    Documentation only.

### Fixed

- Terraform tag consistency (#25)
  - The `add_default_tags` variable description listed a `createdOn` tag that was never applied
    (only `source` and `sharePointVersion` are set); the description now matches the actual
    tags. The Azure Bastion public IP (`azurerm_public_ip.bastion_pip`) hardcoded `tags = {}`
    and is now tagged with `local.tags` like every other resource.

## [1.0.0] - 2026-07-03

First release of ARMConfigKit — a Terraform lab that provisions a SharePoint
Subscription Edition farm on Azure using Azure Verified Modules (AVM), as the
infrastructure companion to
[SPSConfigKit](https://github.com/luigilink/SPSConfigKit).

### Added

- Terraform lab under `terraform/` that provisions a SharePoint Subscription Edition
  farm on Azure via Azure Verified Modules: resource group, virtual network, network
  security group, optional Azure Bastion, and a data-driven set of Windows VMs (PDC,
  PULL, SQL, APP, SCH, WFE, OOS, SWM, ARR).
  - Configurable through `terraform.tfvars`: `arm_subscription_id`, the required
    `adds_domain_admin_username` / `adds_domain_admin_password` (with Azure Windows
    validation — 1-20 char username, 12-123 char password), `resource_group_name`,
    `resource_short_name` (derived from the resource group name when empty),
    `location`, `enable_azure_bastion`, `enable_availability_zones` (non-zonal by
    default to avoid single-zone capacity restrictions and regions without a zonal
    Bastion), `auto_shutdown_time`, and the `vms_informations` map.
  - Single source of truth for region and naming: every resource inherits the
    resource group's location, and resource names use a prefix derived from the
    resource group name.
  - `terraform/outputs.tf` exposing the resource group name and location, the admin
    username, a map of each VM to its private IP, the VM resource IDs and the Azure
    Bastion host name.
- `scripts/StartAzVM.ps1` — a PowerShell 7 helper that re-applies the
  `StandardSSD_LRS` SKU to every managed disk in the resource group
  (deallocate → `az disk update` → start). It processes the VMs concurrently with
  `ForEach-Object -Parallel`, defaults to a dry-run (`$whatIf = $true`), validates
  the `az` calls, prints a per-VM summary and exits non-zero on failure.
- Tests and CI: the Pester suite `tests/StartAzVM.Tests.ps1` (15 tests, no real
  Azure calls); `.github/workflows/pester.yml` (Pester + PSScriptAnalyzer) and
  `.github/workflows/terraform.yml` (`fmt` / `init` / `validate`) running on pull
  requests; `PSScriptAnalyzerSettings.psd1` and `.gitattributes` enforcing the
  code-quality and encoding policies.
- Repository scaffolding and documentation: `README.md`, `CODE_OF_CONDUCT.md`,
  `.editorconfig`, `.github/` issue/PR templates, release and wiki workflows, and the
  `wiki/` guide (Home, Getting-Started, Configuration, Usage).
