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

If `adds_domain_admin_password` is left empty, the configuration generates a random
password via the `random_password` resource.

## Common optional variables

| Variable                | Default              | Description                                  |
| ----------------------- | -------------------- | -------------------------------------------- |
| `resource_group_name`   | `rg-sps-se`          | Resource group to create/use.                |
| `location`              | `francecentral`      | Azure region.                                |
| `adds_fqdn`             | `contoso.com`        | Active Directory domain FQDN.                |
| `sharepoint_version`    | `Subscription-Latest`| SharePoint farm version.                     |
| `enable_azure_bastion`  | `true`               | Provision Azure Bastion.                     |
| `auto_shutdown_time`    | `2000`               | Auto-shutdown time (HHmm), `9999` to disable.|

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
