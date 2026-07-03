# Configuration

All inputs are defined in `terraform/variables.tf`. Sensitive values have **empty
defaults** and must be supplied through `terraform.tfvars` (git-ignored). A tracked
`terraform.tfvars.example` documents the expected shape.

## Required variables

| Variable                     | Description                                   |
| ---------------------------- | --------------------------------------------- |
| `arm_subscription_id`        | Target Azure subscription ID.                 |
| `adds_domain_admin_username` | Domain administrator username.                |
| `adds_domain_admin_password` | Domain administrator password (sensitive).    |

`adds_domain_admin_password` is **required** and must be a Windows-compliant password
(12-123 characters, with complexity). No password is generated — you provide your own.
`adds_domain_admin_username` is also required (1-20 characters, not a reserved name).

## Common optional variables

| Variable                    | Default              | Description                                  |
| --------------------------- | -------------------- | -------------------------------------------- |
| `resource_group_name`       | `RG-SPSE-SmallFarm`  | Resource group to create/use.                |
| `location`                  | `francecentral`      | Azure region.                                |
| `adds_fqdn`                 | `contoso.com`        | Active Directory domain FQDN.                |
| `sharepoint_version`        | `Subscription-Latest`| SharePoint farm version.                     |
| `enable_azure_bastion`      | `true`               | Provision Azure Bastion.                     |
| `enable_availability_zones` | `false`              | Pin VMs/PIPs/Bastion to zones 1/2/3.         |
| `auto_shutdown_time`        | `2000`               | Auto-shutdown time (HHmm), `9999` to disable.|

## Availability zones

By default (`enable_availability_zones = false`) the VMs, their public IPs and the
Azure Bastion are deployed **non-zonal**. This is the recommended lab setting: it
avoids single-zone capacity restrictions (`SkuNotAvailable`) and works in regions
that do not support a zonal Azure Bastion (e.g. France Central).

Set `enable_availability_zones = true` only in a region that supports availability
zones **and** a zonal Bastion (e.g. West Europe). When enabled, the VMs use a single
random zone and the public IPs / Bastion span zones 1/2/3.

## Auto-shutdown

The lab VMs are configured to auto-shutdown and deallocate at `auto_shutdown_time`
(24h `HHmm` format) to save cost — this is a lab convenience, not a production
default. To **disable** the automatic shutdown, set the value to `9999`:

```hcl
auto_shutdown_time = "9999"
```

## Defining the VMs

The farm topology is data-driven through the `vms_informations` map. Add, remove or
resize machines by editing this map — the design is **not fixed** to the sample set
of servers. Each entry defines a `name`, `PrivateIPAddress`, `size` and `tags`.

See `terraform/variables.tf` for the full list of variables and their validation
rules.
