# Naming conventions for the generic landing zone spoke
locals {
  # Core naming components
  env_prefix = lower(var.environment)
  service    = var.workload_role

  # Azure Region Abbreviation Mapping
  region_abbreviations = {
    "Australia Central"    = "ac"
    "Australia Central 2"  = "ac2"
    "Australia East"       = "ae"
    "Australia Southeast"  = "ase"
    "Brazil South"         = "bs"
    "Canada Central"       = "cc"
    "Canada East"          = "ce"
    "Central India"        = "ci"
    "Central US"           = "cus"
    "East Asia"            = "ea"
    "East US"              = "eus"
    "East US 2"            = "eus2"
    "France Central"       = "fc"
    "France South"         = "fs"
    "Germany North"        = "gn"
    "Germany West Central" = "gwc"
    "Japan East"           = "je"
    "Japan West"           = "jw"
    "Korea Central"        = "kc"
    "Korea South"          = "ks"
    "North Central US"     = "ncus"
    "North Europe"         = "ne"
    "Norway East"          = "noe"
    "Norway West"          = "now"
    "South Africa North"   = "san"
    "South Africa West"    = "saw"
    "South Central US"     = "scus"
    "South India"          = "si"
    "Southeast Asia"       = "sea"
    "Sweden Central"       = "sc"
    "Sweden South"         = "ss"
    "Switzerland North"    = "sn"
    "Switzerland West"     = "sw"
    "UAE Central"          = "uc"
    "UAE North"            = "un"
    "UK South"             = "uks"
    "UK West"              = "ukw"
    "West Central US"      = "wcus"
    "West Europe"          = "we"
    "West India"           = "wi"
    "West US"              = "wus"
    "West US 2"            = "wus2"
    "West US 3"            = "wus3"
  }

  # Standardized location abbreviation using proper mapping
  location_abbr = lookup(local.region_abbreviations, var.location,
    substr(lower(replace(var.location, " ", "")), 0, 3)
  )

  # Standard resource naming patterns - Network RG is the main/default RG
  spoke_names = {
    resource_group          = var.spoke_config.resource_group_name != null ? var.spoke_config.resource_group_name : "rg-${local.env_prefix}-${local.service}-${local.location_abbr}-network"
    network_resource_group  = var.spoke_config.resource_group_name != null ? var.spoke_config.resource_group_name : "rg-${local.env_prefix}-${local.service}-${local.location_abbr}-network"
    storage_resource_group  = "rg-${local.env_prefix}-${local.service}-${local.location_abbr}-storage"
    servers_resource_group  = "rg-${local.env_prefix}-${local.service}-${local.location_abbr}-servers"
    backup_resource_group   = "rg-${local.env_prefix}-${local.service}-${local.location_abbr}-backup"
    recovery_resource_group = "rg-${local.env_prefix}-${local.service}-${local.location_abbr}-recovery"
    virtual_network         = "vnet-${local.env_prefix}-${local.service}-${local.location_abbr}"
    network_security_group  = "nsg-${local.env_prefix}-${local.service}-${local.location_abbr}"
    route_table             = "rt-${local.env_prefix}-${local.service}-${local.location_abbr}"
    storage_account         = replace(lower("st${local.env_prefix}${local.service}${local.location_abbr}"), "[^a-z0-9]", "")
    recovery_vault          = "rsv-${local.env_prefix}-${local.service}-${local.location_abbr}"
    key_vault               = lower("kv${local.env_prefix}${local.service}${local.location_abbr}${random_string.spoke_naming.result}")
    availability_set        = "avs-${local.env_prefix}-${local.service}-${local.location_abbr}"
    vm_prefix               = "vm-${local.env_prefix}-${local.service}"
    nic_prefix              = "nic-${local.env_prefix}-${local.service}"
    disk_prefix             = "disk-${local.env_prefix}-${local.service}"

    # Enhanced naming functions for multiple resources
    nic_name_template       = "nic-${local.env_prefix}-${local.service}-%s-%02d"
    data_disk_name_template = "disk-data-${local.env_prefix}-${local.service}-%s-%02d"
    os_disk_name_template   = "disk-os-${local.env_prefix}-${local.service}-%s"
  }

  # Role-specific naming overrides
  role_specific_names = merge(local.spoke_names, {
    # Identity-specific naming (standardized with env/location)
    domain_controllers_subnet = var.workload_role == "identity" ? "snet-domain-controllers-${local.env_prefix}-${local.location_abbr}" : null
    domain_controllers_nsg    = var.workload_role == "identity" ? "nsg-${local.env_prefix}-domain-controllers-${local.location_abbr}" : null
    os_disk_prefix            = var.workload_role == "identity" ? "disk-os-dc-${local.env_prefix}-${local.location_abbr}" : "disk-os-${local.service}-${local.env_prefix}-${local.location_abbr}"
    data_disk_name_prefix     = var.workload_role == "identity" ? "disk-data-dc-${local.env_prefix}-${local.location_abbr}" : "disk-data-${local.service}-${local.env_prefix}-${local.location_abbr}"
  })

  # Storage account naming with length constraints
  storage_account_names = {
    general = substr(local.spoke_names.storage_account, 0, 24)
  }

  # Key Vault naming with length constraints (max 24 characters)
  key_vault_names = {
    main = length(local.spoke_names.key_vault) <= 24 ? local.spoke_names.key_vault : substr(local.spoke_names.key_vault, 0, 24)
  }

  # Tags with role-specific additions
  spoke_tags = merge(var.default_tags, {
    Workload = title(var.workload_role)
  })
}
