# Usage

## Deploy / update the lab

```bash
cd terraform
terraform plan
terraform apply
```

On a brand-new or capacity-constrained subscription, if the apply hits transient
`404 ResourceNotFound` / "inconsistent result" errors from Azure Resource Manager,
re-run it with reduced parallelism (`terraform apply -parallelism=3`); Terraform
converges over repeated applies. See [Getting-Started](Getting-Started) for details.

## Tear down

```bash
terraform destroy
```

## Auto-shutdown

By default the lab VMs auto-shutdown and deallocate every evening at
`auto_shutdown_time` to save cost. In production the farm VMs are normally left
running — set `auto_shutdown_time = "9999"` in your `terraform.tfvars` to disable the
automatic shutdown. See [Configuration](Configuration) for details.

## Re-apply the StandardSSD_LRS disk SKU

An Azure policy can periodically downgrade the lab's managed disks back to
Standard HDD (`Standard_LRS`). `scripts/StartAzVM.ps1` puts every managed disk in the
resource group back to `StandardSSD_LRS`. For each VM it deallocates the machine,
runs `az disk update` on the OS and data disks, then starts the VM again.

> This script is a lab convenience — in production the VMs are typically not stopped,
> so disk-SKU drift does not occur.

```powershell
# Requires: Azure CLI installed and logged in (az login), PowerShell 7+
./scripts/StartAzVM.ps1            # apply
./scripts/StartAzVM.ps1 -WhatIf    # preview only: nothing is deallocated, started or changed
```

The script is configured through parameters; the defaults are the values used by the lab:

| Parameter | Default | Purpose |
|---|---|---|
| `-ResourceGroup` | `ARMConfigKit` | Resource group to process. |
| `-TargetSku` | `StandardSSD_LRS` | Desired disk SKU (`Standard_LRS`, `StandardSSD_LRS`, `Premium_LRS`, `PremiumV2_LRS`). |
| `-DeallocateVM` | `$true` | Deallocate each VM before changing its disk SKU. |
| `-StartAfter` | `$true` | Start the VM again if the script deallocated it. |
| `-ThrottleLimit` | `5` | Maximum number of VMs processed concurrently. |
| `-WhatIf` | off | Simulation: lists what would be done without doing it. |

Boolean parameters take the `-Name:$false` form, e.g. `./scripts/StartAzVM.ps1 -StartAfter:$false`.

> The script no longer defaults to a dry run: run it with `-WhatIf` to simulate.
> `-Confirm` is not supported, because the VMs are processed in parallel runspaces.

## Hand-off to SPSConfigKit

Once the VMs are running, configure the SharePoint farm with
[SPSConfigKit](https://github.com/luigilink/SPSConfigKit). ARMConfigKit only owns the
Azure infrastructure; SPSConfigKit owns the domain, SQL and SharePoint configuration.
