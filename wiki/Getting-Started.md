# Getting Started

## Prerequisites

| Tool       | Version | Notes                                            |
| ---------- | ------- | ------------------------------------------------ |
| Terraform  | ≥ 1.5   | <https://developer.hashicorp.com/terraform>      |
| Azure CLI  | recent  | `az login` before running Terraform              |
| PowerShell | 7+      | for the helper scripts under `scripts/`          |

You also need an Azure subscription with enough quota for the VM sizes defined in
`terraform/variables.tf` (`vms_informations`).

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
- `adds_domain_admin_username`
- `adds_domain_admin_password`

> ⚠️ `terraform.tfvars` and state files are **git-ignored** — they hold secrets and
> your resource layout. Never commit them.

## 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

## 4. Next: configure SharePoint

Once the VMs are up, continue with
[SPSConfigKit](https://github.com/luigilink/SPSConfigKit) to configure the domain,
SQL Server and the SharePoint farm.
