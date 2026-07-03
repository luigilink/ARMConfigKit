# ARMConfigKit - Release Notes

## [Unreleased]

First release of ARMConfigKit — a Terraform lab that provisions a SharePoint
Subscription Edition farm on Azure using Azure Verified Modules, as the
infrastructure companion to [SPSConfigKit](https://github.com/luigilink/SPSConfigKit).

### Added

- Terraform configuration under `terraform/` (resource group, virtual network,
  network security groups, Azure Bastion and a data-driven set of farm VMs).
- `scripts/StartAzVM.ps1` disk-SKU remediation helper.
- Repository scaffolding and wiki documentation.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md).
