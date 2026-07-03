# Change log for ARMConfigKit

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial repository scaffolding: `README.md`, `CHANGELOG.md`, `RELEASE-NOTES.md`,
  `CODE_OF_CONDUCT.md`, `.editorconfig`, `.gitignore`, `.github/` templates and
  workflows (release + wiki), and the `wiki/` documentation set.
- Terraform lab under `terraform/` provisioning a SharePoint Subscription Edition
  farm on Azure via Azure Verified Modules (resource group, virtual network,
  network security groups, Azure Bastion and the farm virtual machines).
- `scripts/StartAzVM.ps1` — re-applies the `StandardSSD_LRS` SKU to every managed
  disk in the resource group.
