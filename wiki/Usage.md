# Usage

## Deploy / update the lab

```bash
cd terraform
terraform plan
terraform apply
```

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
./scripts/StartAzVM.ps1
```

Key script settings (top of the file):

- `$resourceGroup` — the resource group to process.
- `$targetSku` — desired disk SKU (`StandardSSD_LRS`).
- `$whatIf` — set to `$true` for a dry run.
- `$deallocateVM` / `$startAfter` — deallocate before changing SKU and restart after.

## Hand-off to SPSConfigKit

Once the VMs are running, configure the SharePoint farm with
[SPSConfigKit](https://github.com/luigilink/SPSConfigKit). ARMConfigKit only owns the
Azure infrastructure; SPSConfigKit owns the domain, SQL and SharePoint configuration.
