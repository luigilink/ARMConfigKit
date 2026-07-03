# 1. Specify the version of the AzureRM Provider to use
terraform {
  required_version = ">= 1.14.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.80.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "=2.7.0" # pin to avoid identity bug seen in 2.8.0
    }
  }
}

# 2. Configure the AzureRM Provider
provider "azurerm" {
  # The AzureRM Provider supports authenticating using via the Azure CLI, a Managed Identity
  # and a Service Principal. More information on the authentication methods supported by
  # the AzureRM Provider can be found here:
  # https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs#authenticating-to-azure

  # The features block allows changing the behaviour of the Azure Provider, more
  # information can be found here:
  # https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/features-block
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    virtual_machine {
      skip_shutdown_and_force_delete = false
      delete_os_disk_on_deletion     = false
    }
    template_deployment {
      delete_nested_items_during_deletion = true
    }
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
  subscription_id = var.arm_subscription_id
}

locals {
  az_resource_group_name     = var.resource_group_name
  az_resource_short_name     = "rgspsmfarm"
  resourceGroupNameFormatted = replace(replace(replace(replace(local.az_resource_group_name, ".", "-"), "(", "-"), ")", "-"), "_", "-")
  az_resource_group_location = var.location
  enable_telemetry           = true
  license_type               = "Windows_Server"
  create_rdp_rule            = lower(var.rdp_traffic_rule) == "no" ? false : true
  network_settings = {
    vNetPrivatePrefix   = "10.1.0.0/16"
    mainSubnetPrefix    = "10.1.1.0/24"
    bastionSubnetPrefix = "10.1.0.0/26"
  }
  default_tags = {
    source            = "terraform:luigilink/sharepoint/azurerm"
    sharePointVersion = var.sharepoint_version
  }
  tags = merge(
    var.add_default_tags ? local.default_tags : {},
    var.tags != null ? var.tags : {}
  )
}

# Create modules for naming and regions
# These modules are used to generate consistent names and select regions based on availability zones
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.3"
}

module "regions" {
  source           = "Azure/avm-utl-regions/azurerm"
  version          = "0.9.1"
  enable_telemetry = local.enable_telemetry
}
resource "random_integer" "zone_index" {
  max = length(module.regions.regions_by_name[var.location].zones)
  min = 1
}

# Create a resource group
resource "azurerm_resource_group" "rg" {
  name     = local.az_resource_group_name
  location = local.az_resource_group_location
}

# Create virtual network
module "vnet" {
  source           = "Azure/avm-res-network-virtualnetwork/azurerm"
  version          = "0.17.1"
  name             = "${local.az_resource_short_name}-VNET"
  location         = azurerm_resource_group.rg.location
  parent_id        = azurerm_resource_group.rg.id
  tags             = local.tags
  enable_telemetry = local.enable_telemetry
  address_space    = [local.network_settings.vNetPrivatePrefix]
  subnets = {
    vm_subnet_1 = {
      name                            = "${local.az_resource_short_name}-VNET-Subnet1"
      address_prefixes                = [local.network_settings.mainSubnetPrefix]
      default_outbound_access_enabled = false
      network_security_group = {
        id = module.nsg_subnet_main.resource_id
      }
    }
    "AzureBastionSubnet" = {
      name                            = "AzureBastionSubnet"
      address_prefixes                = [local.network_settings.bastionSubnetPrefix]
      default_outbound_access_enabled = false
    }
  }
  depends_on = [
    azurerm_resource_group.rg
  ]
}
# Create a public IP address for Azure Bastion
resource "azurerm_public_ip" "bastion_pip" {
  name                = "${local.az_resource_short_name}-VNET-IPv4"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = {}
  zones               = ["1", "2", "3"]
}

# Create Network security group
module "nsg_subnet_main" {
  source              = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version             = "0.5.1"
  name                = "${local.az_resource_short_name}-VNET-NSG"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
  enable_telemetry    = local.enable_telemetry
  security_rules = local.create_rdp_rule ? {
    allow_rdp_rule = {
      name                       = "allow-rdp-rule"
      description                = "Allow RDP"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefix      = var.rdp_traffic_rule
      destination_address_prefix = "*"
      access                     = "Allow"
      priority                   = 100
      direction                  = "Inbound"
    }
  } : {}
}

# Create All the Virtual Machines from variables vms_informations
module "vm" {
  for_each = var.vms_informations

  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "0.20.0"

  # Zone: reuse your existing random value or make it per-VM later
  zone = random_integer.zone_index.result

  # Basic identity
  name                = each.value.name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  # Windows host constraints: <= 15 chars for NetBIOS computer name
  computer_name = substr(each.value.name, 0, 15)

  # Size / OS / licensing
  sku_size                   = each.value.size
  os_type                    = "Windows"
  license_type               = local.license_type
  encryption_at_host_enabled = false
  secure_boot_enabled        = true
  vtpm_enabled               = true

  # Timezone
  timezone = var.az_time_zone

  # Tags: merge common + per-VM
  tags = each.value.tags

  # NIC and IP configuration
  network_interfaces = {
    network_interface_1 = {
      name = "${local.az_resource_short_name}-${each.value.name}-NIC1"
      ip_configurations = {
        ip_configuration_1 = {
          name                          = "${local.az_resource_short_name}-${each.value.name}-IPC1"
          private_ip_subnet_resource_id = module.vnet.subnets["vm_subnet_1"].resource_id
          private_ip_address_allocation = "Static"
          private_ip_address            = each.value.PrivateIPAddress
          create_public_ip_address      = var.outbound_access_method == "PublicIPAddress" ? true : false
          public_ip_address_name        = "${local.az_resource_short_name}-${each.value.name}-PIP"
        }
      }
    }
  }
  # Only configure the domain name label if the user has chosen to add a name to public IP addresses, otherwise set it to null to avoid errors since the public IP won't be created. The domain name label must be unique across Azure, so we use the resource group name and VM name to try to ensure uniqueness.
  public_ip_configuration_details = {
    domain_name_label = lower(trimspace(var.add_name_to_public_ip_addresses)) == "yes" ? "${lower(local.resourceGroupNameFormatted)}-${lower(each.value.name)}" : null
    zones             = ["1", "2", "3"]
  }
  # Account credentials: the admin username/password are required user-provided
  # inputs (no password is generated). generate_admin_password_or_ssh_key is false
  # because the password is always supplied. SSH keys are not used (Windows).
  account_credentials = {
    admin_credentials = {
      username                           = var.adds_domain_admin_username
      password                           = var.adds_domain_admin_password
      generate_admin_password_or_ssh_key = false
    }
  }
  # Disk settings and image reference
  os_disk = {
    name                 = "${local.az_resource_short_name}-${each.value.name}-OSDisk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    size_gb              = 128
  }
  data_disk_managed_disks = {
    data_disk = {
      caching              = "ReadWrite"
      storage_account_type = "StandardSSD_LRS"
      name                 = "${local.az_resource_short_name}-${each.value.name}-DataDisk"
      disk_size_gb         = 256
      lun                  = 0
    }
    logs_disk = {
      caching              = "ReadWrite"
      storage_account_type = "StandardSSD_LRS"
      name                 = "${local.az_resource_short_name}-${each.value.name}-LogsDisk"
      disk_size_gb         = 128
      lun                  = 1
    }
  }
  source_image_reference = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }
  # Auto-shutdown schedule
  shutdown_schedules = {
    auto_shutdown = {
      enabled               = var.auto_shutdown_time == "9999" ? false : true
      daily_recurrence_time = var.auto_shutdown_time == "9999" ? "0000" : var.auto_shutdown_time
      timezone              = var.az_time_zone
      notification_settings = {
        enabled = false
      }
    }
  }

  depends_on = [
    azurerm_resource_group.rg,
    module.vnet
  ]
}

# Resources for Azure Bastion Basic SKU
module "azure_bastion" {
  count               = var.enable_azure_bastion ? 1 : 0
  source              = "Azure/avm-res-network-bastionhost/azurerm"
  version             = "0.8.2"
  name                = "${local.az_resource_short_name}-BASTION"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
  enable_telemetry    = local.enable_telemetry
  sku                 = "Basic"
  zones               = ["1", "2", "3"]
  ip_configuration = {
    name                 = "IpConf"
    subnet_id            = module.vnet.subnets["AzureBastionSubnet"].resource_id
    public_ip_address_id = azurerm_public_ip.bastion_pip.id
    create_public_ip     = false
  }
}
