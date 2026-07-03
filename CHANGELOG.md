# Change log for ARMConfigKit

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

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
