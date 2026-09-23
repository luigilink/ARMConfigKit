# ARMConfigKit

![Latest release](https://img.shields.io/github/v/release/luigilink/ARMConfigKit.svg?style=flat)
![Latest release date](https://img.shields.io/github/release-date/luigilink/ARMConfigKit.svg?style=flat)
![Total downloads](https://img.shields.io/github/downloads/luigilink/ARMConfigKit/total.svg?style=flat)  
![Issues opened](https://img.shields.io/github/issues/luigilink/ARMConfigKit.svg?style=flat)
![Last commit](https://img.shields.io/github/last-commit/luigilink/ARMConfigKit.svg?style=flat)
![License](https://img.shields.io/github/license/luigilink/ARMConfigKit.svg?style=flat)  
![CI Terraform](https://github.com/luigilink/ARMConfigKit/actions/workflows/terraform.yml/badge.svg)
![CI Pester](https://github.com/luigilink/ARMConfigKit/actions/workflows/pester.yml/badge.svg)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md)

## Description

ARMConfigKit is a Terraform lab that provisions a SharePoint Subscription Edition
farm on Azure using the [Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/).
It stands up the full supporting infrastructure — resource group, virtual network,
network security groups, Azure Bastion and the farm virtual machines — so you get a
clean, repeatable environment to install and test SharePoint on.

It is the **infrastructure companion to [SPSConfigKit](https://github.com/luigilink/SPSConfigKit)**:
ARMConfigKit builds the Azure VMs, then SPSConfigKit configures the SharePoint farm
on top of them with PowerShell Desired State Configuration. The two projects are
linked by documentation only — this repository contains no DSC content.

[Download the latest release, click here!](https://github.com/luigilink/ARMConfigKit/releases/latest)

## Topology

The sample provisions a small SharePoint Subscription Edition farm (PDC, PULL, SQL,
APP, SCH, WFE, OOS, SWM, ARR), but the design is **not limited to a fixed number of
machines** — the VM list is data-driven (`vms_informations` in
`terraform/variables.tf`) and SPSConfigKit scales to any number of nodes. See the
[Topology](https://github.com/luigilink/ARMConfigKit/wiki/Topology) wiki page for the
full role/VM breakdown.

## Requirements

- [Terraform](https://developer.hashicorp.com/terraform/downloads) 1.5 or later
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az login`)
- An Azure subscription with quota for the VM sizes above
- [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)
  for the helper scripts under `scripts/`

## Getting started

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # then fill in your values
terraform init
terraform plan
terraform apply
```

> ⚠️ **Never commit `terraform.tfvars` or state files.** They contain your
> subscription ID, admin credentials and resource layout. The `.gitignore` already
> excludes `*.tfvars` (except `*.tfvars.example`), `*.tfstate*` and `.terraform/`.

See the [ARMConfigKit Wiki](https://github.com/luigilink/ARMConfigKit/wiki) for the
full walkthrough.

## Scripts

- `scripts/StartAzVM.ps1` — re-applies the `StandardSSD_LRS` SKU to every managed
  disk in the resource group (deallocate → `az disk update` → start). Useful because
  an Azure policy can periodically downgrade lab disks back to Standard HDD.

## Documentation

For detailed usage, configuration and getting-started information, visit the
[ARMConfigKit Wiki](https://github.com/luigilink/ARMConfigKit/wiki).

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md).
