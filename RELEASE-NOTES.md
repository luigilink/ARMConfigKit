# ARMConfigKit - Release Notes

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
    `armconfigkit` (e.g. `armconfigkit-VNET`). Defaults and documentation only — no change to
    the deployment behaviour.
- Polished the README and wiki (#23)
  - Enriched the README badge row (latest release/version, license, CI Terraform and Pester
    status, last commit) and moved the full `Topology` table out of the README into a dedicated
    `Topology` wiki page. Added a `_Sidebar.md` wiki navigation (mirroring the other luigilink
    kits) and refreshed the `Home` page list.

### Fixed

- Terraform tag consistency (#25)
  - The `add_default_tags` variable description listed a `createdOn` tag that was never applied
    (only `source` and `sharePointVersion` are set); the description now matches the actual
    tags. The Azure Bastion public IP (`azurerm_public_ip.bastion_pip`) hardcoded `tags = {}`
    and is now tagged with `local.tags` like every other resource.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md).
