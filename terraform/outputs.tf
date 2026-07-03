# Outputs for the ARMConfigKit lab deployment.

output "resource_group_name" {
  description = "Name of the resource group hosting the lab."
  value       = azurerm_resource_group.rg.name
}

output "resource_group_location" {
  description = "Azure region where the lab is deployed."
  value       = azurerm_resource_group.rg.location
}

output "admin_username" {
  description = "The domain administrator username configured on the VMs."
  value       = var.adds_domain_admin_username
}

output "vm_private_ips" {
  description = "Map of each VM name to its static private IP address."
  value       = { for k, v in var.vms_informations : v.name => v.PrivateIPAddress }
}

output "vm_resource_ids" {
  description = "Map of each VM key to its Azure resource ID."
  value       = { for k, v in module.vm : k => v.resource_id }
}

output "bastion_name" {
  description = "Name of the Azure Bastion host, or null when Bastion is disabled."
  value       = var.enable_azure_bastion ? module.azure_bastion[0].name : null
}
