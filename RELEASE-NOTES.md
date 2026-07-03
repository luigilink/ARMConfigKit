# ARMConfigKit - Release Notes

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

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md).
