# ARMConfigKit

Welcome to the **ARMConfigKit** wiki.

ARMConfigKit is a Terraform lab that provisions a SharePoint Subscription Edition
farm on Azure using [Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/).
It is the infrastructure companion to
[SPSConfigKit](https://github.com/luigilink/SPSConfigKit): ARMConfigKit builds the
Azure VMs, then SPSConfigKit configures SharePoint on top of them with PowerShell
Desired State Configuration.

## Pages

- **[Getting-Started](Getting-Started)** — prerequisites and first deployment.
- **[Configuration](Configuration)** — variables and `terraform.tfvars`.
- **[Usage](Usage)** — day-to-day operations, `StartAzVM.ps1`, and the hand-off to
  SPSConfigKit.

## How the two kits fit together

```text
ARMConfigKit (Terraform)        SPSConfigKit (DSC)
------------------------        ------------------
RG / VNet / NSG / Bastion  -->  Domain + SQL + SharePoint farm
Farm VMs (PDC, SQL, ...)   -->  Roles, service accounts, config
```

ARMConfigKit stops once the VMs are running. From there, follow the SPSConfigKit
documentation to configure the farm.
