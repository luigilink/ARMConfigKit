# Getting Started

## Prerequisites

| Tool       | Version | Notes                                            |
| ---------- | ------- | ------------------------------------------------ |
| Terraform  | ≥ 1.14  | <https://developer.hashicorp.com/terraform> — see [Terraform versions](#terraform-versions) |
| Azure CLI  | recent  | `az login` before running Terraform              |
| PowerShell | 7+      | for the helper scripts under `scripts/`          |

You also need an Azure subscription with enough quota for the VM sizes defined in
`vms_informations` (default in `terraform/variables.tf`, overridable in `terraform/terraform.tfvars`).

### Terraform versions

`terraform/main.tf` declares `required_version = ">= 1.14.0"`. That floor is above the one of every
module in use (the highest is `>= 1.10` for the `vm` module), and the modules already cap Terraform
below 2.0, so no upper bound is added. The table records what has actually been exercised, which is
narrower than what the constraint allows.

| Terraform | `init` / `validate` / `fmt` | `plan` | `apply` | Notes |
| --------- | --------------------------- | ------ | ------- | ----- |
| 1.15.5    | OK (also the CI version)    | OK     | OK      | Reference version; the lab state was last written by it. |
| 1.17.1    | OK (checked 2026-10-30)     | OK, identical to 1.15.5 | **Not tested** | Evaluated on a copy of `terraform/`. |

- The 1.17.1 check was `terraform init -backend=false`, `validate`, `fmt -check` and a read-only
  `plan -lock=false` on a copy of the project. Providers matched `.terraform.lock.hcl`, the plan was
  identical to the 1.15.5 one, and the only warnings are the `enable_automatic_updates` deprecation
  from the `vm` module (removed in azurerm 5.0), identical on both versions.
- **`apply` has not been run with 1.17.1.** Do not assume it behaves like 1.15.5 until it has been
  tried on the lab.
- Keep a copy of `terraform.tfstate` before the first `apply` with a new Terraform version. An apply
  rewrites the state with that version, and going back to the previous version has not been tested
  here.
- Versions below 1.15.5 are allowed by `required_version` but have not been exercised.
- The provider versions are pinned (`azurerm` `=4.81.0`, `azapi` `=2.7.0`) and recorded in the tracked
  `.terraform.lock.hcl`: changing the Terraform CLI version does not change them.

## 1. Authenticate to Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
```

## 2. Provide your values

Copy the example variables file and fill in your own values:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set at least:

- `arm_subscription_id`
- `adds_domain_admin_username` (required, 1-20 chars, not a reserved name)
- `adds_domain_admin_password` (required, Windows rules: 12-123 chars with complexity)

> ⚠️ `terraform.tfvars` and state files are **git-ignored** — they hold secrets and
> your resource layout. Never commit them.

## 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

> **Tip — fresh or capacity-constrained subscriptions.** Applying the full farm
> creates ~108 resources at once. On a brand-new subscription (or a region under
> load), Azure Resource Manager's eventual consistency can lag behind Terraform's
> read-after-write and surface transient `404 ResourceNotFound` /
> `Provider produced inconsistent result` errors. If that happens, re-run the apply
> with reduced parallelism so ARM can keep up:
>
> ```bash
> terraform apply -parallelism=3
> ```
>
> Terraform converges over repeated applies. A subscription that has already hosted
> deployments usually applies cleanly at the default parallelism.

## 4. Next: configure SharePoint

Once the VMs are up, continue with
[SPSConfigKit](https://github.com/luigilink/SPSConfigKit) to configure the domain,
SQL Server and the SharePoint farm.
