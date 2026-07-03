variable "resource_group_name" {
  default     = "rg-sps-se"
  description = "Name of the resource group to create and/or use for this deployment."
}

variable "arm_subscription_id" {
  description = "The subscription ID to use for this deployment."
  default     = ""
}

variable "adds_fqdn" {
  default     = "contoso.com"
  description = "Fully qualified domain name (FQDN) of the Active Directory domain."
}

variable "adds_domain_netbios_name" {
  default     = "CONTOSO"
  description = "NetBIOS name of the Active Directory domain."
}

variable "adds_domain_admin_username" {
  type        = string
  description = "Username of the Active Directory domain administrator. Required — you must provide your own value."
  validation {
    condition     = !contains(["admin", "administrator"], lower(var.adds_domain_admin_username))
    error_message = "admin and administrator are reserved words and cannot be used as the domain administrator username."
  }
  validation {
    condition     = length(var.adds_domain_admin_username) >= 1 && length(var.adds_domain_admin_username) <= 20
    error_message = "adds_domain_admin_username must be between 1 and 20 characters (Windows admin username limit)."
  }
}

variable "adds_domain_admin_password" {
  type        = string
  description = "Password of the Active Directory domain administrator. Required — you must provide your own value (no password is generated). Azure requires a Windows admin password of 12-123 characters with complexity."
  sensitive   = true
  validation {
    condition     = length(var.adds_domain_admin_password) >= 12 && length(var.adds_domain_admin_password) <= 123
    error_message = "adds_domain_admin_password must be between 12 and 123 characters (Azure Windows VM requirement)."
  }
}

variable "location" {
  type        = string
  default     = "francecentral"
  description = "The Azure region where this and supporting resources should be deployed."
  nullable    = false
}

variable "az_time_zone" {
  default     = "Romance Standard Time"
  description = "Time zone of the virtual machines. Type '[TimeZoneInfo]::GetSystemTimeZones().Id' in PowerShell to get the list."
  validation {
    condition = contains([
      "Dateline Standard Time",
      "UTC-11",
      "Aleutian Standard Time",
      "Hawaiian Standard Time",
      "Marquesas Standard Time",
      "Alaskan Standard Time",
      "UTC-09",
      "Pacific Standard Time (Mexico)",
      "UTC-08",
      "Pacific Standard Time",
      "US Mountain Standard Time",
      "Mountain Standard Time (Mexico)",
      "Mountain Standard Time",
      "Central America Standard Time",
      "Central Standard Time",
      "Easter Island Standard Time",
      "Central Standard Time (Mexico)",
      "Canada Central Standard Time",
      "SA Pacific Standard Time",
      "Eastern Standard Time (Mexico)",
      "Eastern Standard Time",
      "Haiti Standard Time",
      "Cuba Standard Time",
      "US Eastern Standard Time",
      "Turks And Caicos Standard Time",
      "Paraguay Standard Time",
      "Atlantic Standard Time",
      "Venezuela Standard Time",
      "Central Brazilian Standard Time",
      "SA Western Standard Time",
      "Pacific SA Standard Time",
      "Newfoundland Standard Time",
      "Tocantins Standard Time",
      "E. South America Standard Time",
      "SA Eastern Standard Time",
      "Argentina Standard Time",
      "Greenland Standard Time",
      "Montevideo Standard Time",
      "Magallanes Standard Time",
      "Saint Pierre Standard Time",
      "Bahia Standard Time",
      "UTC-02",
      "Mid-Atlantic Standard Time",
      "Azores Standard Time",
      "Cape Verde Standard Time",
      "UTC",
      "GMT Standard Time",
      "Greenwich Standard Time",
      "Sao Tome Standard Time",
      "Morocco Standard Time",
      "W. Europe Standard Time",
      "Central Europe Standard Time",
      "Romance Standard Time",
      "Central European Standard Time",
      "W. Central Africa Standard Time",
      "Jordan Standard Time",
      "GTB Standard Time",
      "Middle East Standard Time",
      "Egypt Standard Time",
      "E. Europe Standard Time",
      "Syria Standard Time",
      "West Bank Standard Time",
      "South Africa Standard Time",
      "FLE Standard Time",
      "Israel Standard Time",
      "Kaliningrad Standard Time",
      "Sudan Standard Time",
      "Libya Standard Time",
      "Namibia Standard Time",
      "Arabic Standard Time",
      "Turkey Standard Time",
      "Arab Standard Time",
      "Belarus Standard Time",
      "Russian Standard Time",
      "E. Africa Standard Time",
      "Iran Standard Time",
      "Arabian Standard Time",
      "Astrakhan Standard Time",
      "Azerbaijan Standard Time",
      "Russia Time Zone 3",
      "Mauritius Standard Time",
      "Saratov Standard Time",
      "Georgian Standard Time",
      "Volgograd Standard Time",
      "Caucasus Standard Time",
      "Afghanistan Standard Time",
      "West Asia Standard Time",
      "Ekaterinburg Standard Time",
      "Pakistan Standard Time",
      "Qyzylorda Standard Time",
      "India Standard Time",
      "Sri Lanka Standard Time",
      "Nepal Standard Time",
      "Central Asia Standard Time",
      "Bangladesh Standard Time",
      "Omsk Standard Time",
      "Myanmar Standard Time",
      "SE Asia Standard Time",
      "Altai Standard Time",
      "W. Mongolia Standard Time",
      "North Asia Standard Time",
      "N. Central Asia Standard Time",
      "Tomsk Standard Time",
      "China Standard Time",
      "North Asia East Standard Time",
      "Singapore Standard Time",
      "W. Australia Standard Time",
      "Taipei Standard Time",
      "Ulaanbaatar Standard Time",
      "Aus Central W. Standard Time",
      "Transbaikal Standard Time",
      "Tokyo Standard Time",
      "North Korea Standard Time",
      "Korea Standard Time",
      "Yakutsk Standard Time",
      "Cen. Australia Standard Time",
      "AUS Central Standard Time",
      "E. Australia Standard Time",
      "AUS Eastern Standard Time",
      "West Pacific Standard Time",
      "Tasmania Standard Time",
      "Vladivostok Standard Time",
      "Lord Howe Standard Time",
      "Bougainville Standard Time",
      "Russia Time Zone 10",
      "Magadan Standard Time",
      "Norfolk Standard Time",
      "Sakhalin Standard Time",
      "Central Pacific Standard Time",
      "Russia Time Zone 11",
      "New Zealand Standard Time",
      "UTC+12",
      "Fiji Standard Time",
      "Kamchatka Standard Time",
      "Chatham Islands Standard Time",
      "UTC+13",
      "Tonga Standard Time",
      "Samoa Standard Time",
      "Line Islands Standard Time"
    ], var.az_time_zone)
    error_message = "Invalid time zone value."
  }
}

variable "sharepoint_version" {
  type        = string
  default     = "Subscription-Latest"
  description = "Version of SharePoint farm to create."
  validation {
    condition = contains([
      "Subscription-Latest",
      "Subscription-25H1",
      "Subscription-24H2",
      "Subscription-24H1",
      "Subscription-23H2",
      "Subscription-23H1",
      "Subscription-22H2",
      "Subscription-RTM",
      "2019",
      "2016"
    ], var.sharepoint_version)
    error_message = "Invalid SharePoint farm version."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply on resource."
  nullable    = true
}

variable "add_default_tags" {
  type        = bool
  default     = false
  description = "If true, the default tags will be added to resource. Default tags are: 'source', 'createdOn', and 'sharePointVersion'."
}

variable "rdp_traffic_rule" {
  type        = string
  default     = "No"
  description = <<EOF
    Specify if a rule in the network security groups should allow the inbound RDP traffic:
    - "No" (default): No rule is created, RDP traffic is blocked.
    - "*" or "Internet": RDP traffic is allowed from everywhere.
    - CIDR notation (e.g. 192.168.99.0/24 or 2001:1234::/64) or an IP address (e.g. 192.168.99.0 or 2001:1234::): RDP traffic is allowed from the IP address / pattern specified.
  EOF
}

variable "outbound_access_method" {
  type        = string
  default     = "PublicIPAddress"
  description = <<EOF
    Select how the virtual machines connect to internet.
    IMPORTANT: With AzureFirewallProxy, you need to either enable Azure Bastion, or manually add a public IP address to a virtual machine, to be able to connect to it.
  EOF
  validation {
    condition = contains([
      "PublicIPAddress",
      "AzureFirewallProxy"
    ], var.outbound_access_method)
    error_message = "Invalid value for outbound_access_method."
  }
}

variable "add_name_to_public_ip_addresses" {
  type        = string
  default     = "SharePointVMsOnly"
  description = "Set if the Public IP addresses of virtual machines should have a name label."
  validation {
    condition = contains([
      "No",
      "SharePointVMsOnly",
      "Yes"
    ], var.add_name_to_public_ip_addresses)
    error_message = "Invalid value selected."
  }
}

variable "enable_azure_bastion" {
  type        = bool
  default     = true
  description = "Specify if Azure Bastion Basic should be provisioned. See https://azure.microsoft.com/en-us/services/azure-bastion for more information."
}

variable "auto_shutdown_time" {
  type        = string
  default     = "2000"
  description = "The time (24h HHmm format) at which the virtual machines will automatically be shutdown and deallocated. Set value to '9999' to NOT configure the auto shutdown."
  validation {
    condition     = can(regex("^\\d{4}$", var.auto_shutdown_time))
    error_message = "The auto_shutdown_time value must contain 4 digits."
  }
}

variable "vms_informations" {
  type = map(object({
    name             = string
    PrivateIPAddress = string
    size             = string
    tags             = map(string)
  }))
  default = {
    "pdc" = {
      name             = "PDC1"
      PrivateIPAddress = "10.1.1.4"
      size             = "Standard_D2ads_v5"
      tags             = { role = "PDC" }
    }
    "pull" = {
      name             = "PULL"
      PrivateIPAddress = "10.1.1.10"
      size             = "Standard_D2ads_v5"
      tags             = { role = "PULL" }
    }
    "sql1" = {
      name             = "SQL1"
      PrivateIPAddress = "10.1.1.11"
      size             = "Standard_D2ads_v5"
      tags             = { role = "SQL" }
    }
    "app1" = {
      name             = "APP1"
      PrivateIPAddress = "10.1.1.21"
      size             = "Standard_D4as_v5"
      tags             = { role = "APP" }
    }
    "sch1" = {
      name             = "SCH1"
      PrivateIPAddress = "10.1.1.25"
      size             = "Standard_D4as_v5"
      tags             = { role = "SCH" }
    }
    "wfe1" = {
      name             = "WFE1"
      PrivateIPAddress = "10.1.1.27"
      size             = "Standard_D4as_v5"
      tags             = { role = "WFE" }
    }
    "oos1" = {
      name             = "OOS1"
      PrivateIPAddress = "10.1.1.31"
      size             = "Standard_D2ads_v5"
      tags             = { role = "OOS" }
    }
    "swm1" = {
      name             = "SWM1"
      PrivateIPAddress = "10.1.1.41"
      size             = "Standard_D2ads_v5"
      tags             = { role = "SWM" }
    }
    "arr" = {
      name             = "ARR"
      PrivateIPAddress = "10.1.1.51"
      size             = "Standard_D2ads_v5"
      tags             = { role = "ARR" }
    }
  }
}
