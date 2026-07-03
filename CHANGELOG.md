# Change log for ARMConfigKit

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `terraform/outputs.tf` exposing the resource group name and location, the admin
  username, a map of each VM to its private IP, the VM resource IDs, and the Azure
  Bastion host name (#12).

### Changed

- **Credentials are now user-provided and required** (#12): removed the generated
  `random_password` and the deprecated top-level `admin_username`/`admin_password`
  module inputs; credentials flow only through `account_credentials`.
  `adds_domain_admin_password` is now required with a 12-123 character validation
  (Azure Windows rule) and `adds_domain_admin_username` with a 1-20 character /
  reserved-word validation. This fixes the previously broken "empty password"
  path, where an empty value was passed to Azure and rejected.
- Removed `prevent_destroy` on the resource group so the documented
  `terraform destroy` teardown works (#12).
- Wired `var.resource_group_name` and `var.location` (previously hardcoded in
  locals) so the RG name and deployment region are consistent and configurable;
  defaults preserve current behavior (`RG-SPSE-SmallFarm` / `francecentral`) (#12).

### Changed

- Bump low-risk Terraform versions (#10): `hashicorp/azurerm` provider
  `=4.58.0` → `=4.80.0`, `Azure/naming/azurerm` module `0.4.2` → `0.4.3`, and
  `Azure/avm-res-network-networksecuritygroup/azurerm` module `0.5.0` → `0.5.1`.
  Refreshed `.terraform.lock.hcl` (also relocks the transitive random `3.9.0`, tls
  `4.3.0` and modtm `0.4.0` providers). The `Azure/azapi` provider stays pinned at
  `=2.7.0` and the other AVM modules are unchanged.

### Added

- CI workflow `.github/workflows/terraform.yml` running on pull requests that touch
  `terraform/**`: `terraform fmt -check`, `init -backend=false` and `validate` on
  `ubuntu-latest` (#8).

- Pester test suite `tests/StartAzVM.Tests.ps1` covering `Get-VMDisk`,
  `Get-DiskSkuUpdatePlan`, `Get-DiskSku` and `Set-DiskSku` (15 tests, no real Azure
  calls) (#6).
- CI workflow `.github/workflows/pester.yml` running on pull requests: a Pester job
  (`windows-latest`, `./tests`) and a PSScriptAnalyzer code-quality job that fails on
  any finding under `scripts/` (#6).
- `.gitattributes` locking the encoding/line-ending policy (`*.ps1`/`*.psm1`/`*.psd1`
  UTF-8 BOM + CRLF; Terraform, YAML, Markdown and JSON as LF without BOM) (#6).

### Changed

- Bump `actions/checkout` from v4 to v5 in all workflows (release, wiki, pester) to
  move off the deprecated Node.js 20 runtime (#6).
- `scripts/StartAzVM.ps1` is now testable (#6): the per-disk SKU decision logic was
  extracted into a pure `Get-DiskSkuUpdatePlan` helper (used by the parallel block),
  and a dot-source guard (`$MyInvocation.InvocationName -eq '.'`) prevents the
  remediation from running when the script is dot-sourced by the tests.

- `scripts/StartAzVM.ps1` is now clean under PSScriptAnalyzer (#4): `Set-DiskSku`
  uses `[CmdletBinding(SupportsShouldProcess)]` with `$PSCmdlet.ShouldProcess`
  instead of a hand-rolled `-WhatIf` switch, `Get-VMDisks` was renamed to the
  singular `Get-VMDisk`, and the file is saved as UTF-8 with BOM. A tracked
  `PSScriptAnalyzerSettings.psd1` documents the single intentional exclusion
  (`PSAvoidUsingWriteHost`, since the script is an interactive colour-coded tool).
- `scripts/StartAzVM.ps1` is now safe to run unattended (#4):
  - The `az vm list` call is validated — a non-zero az exit code (expired login,
    wrong/empty resource group, missing permissions) now fails loudly with
    `exit 1` instead of being masked as "No VMs found", and invalid JSON is caught
    instead of throwing an unhandled parser error.
  - The parallel block emits a per-VM result object; the script prints a summary
    table and exits non-zero if any VM had a failed disk update, could not be
    deallocated, or was left deallocated because it failed to start again.
  - `$whatIf` now defaults to `$true` (dry-run) so a first run previews changes
    instead of immediately mutating disks; set it to `$false` to execute.
- `scripts/StartAzVM.ps1` now processes the resource group's VMs concurrently with
  `ForEach-Object -Parallel` (PowerShell 7) instead of a sequential `foreach`,
  speeding up a full disk-SKU remediation pass (#2). Parent-scope variables are
  passed via `$using:`, the `Get-DiskSku` / `Set-DiskSku` / `Get-VMDisks` helpers are
  re-created inside each runspace, and log lines are prefixed with the VM name so the
  interleaved output stays readable. A `$throttleLimit` setting caps concurrency.

### Added

- Initial repository scaffolding: `README.md`, `CHANGELOG.md`, `RELEASE-NOTES.md`,
  `CODE_OF_CONDUCT.md`, `.editorconfig`, `.gitignore`, `.github/` templates and
  workflows (release + wiki), and the `wiki/` documentation set.
- Terraform lab under `terraform/` provisioning a SharePoint Subscription Edition
  farm on Azure via Azure Verified Modules (resource group, virtual network,
  network security groups, Azure Bastion and the farm virtual machines).
- `scripts/StartAzVM.ps1` — re-applies the `StandardSSD_LRS` SKU to every managed
  disk in the resource group.
