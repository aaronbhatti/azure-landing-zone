# AVD Module - Naming Convention
# This file defines the naming standards for all Azure Virtual Desktop resources

locals {
  # Core naming components
  env_prefix = lower(var.environment)

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

  # Random suffix for unique resources
  random_suffix = random_string.avd_naming.result

  # Service identifier for AVD resources
  service = "avd"

  # Resource naming patterns for AVD module
  avd_names = {
    # Resource Groups
    service_resource_group  = "rg-${local.env_prefix}-${local.service}-${local.location_abbr}-service"
    network_resource_group  = "rg-${local.env_prefix}-${local.service}-${local.location_abbr}-network"
    storage_resource_group  = "rg-${local.env_prefix}-${local.service}-${local.location_abbr}-storage"
    hostpool_resource_group = "rg-${local.env_prefix}-${local.service}-${local.location_abbr}-hostpool-standard"

    # Virtual Network
    virtual_network = "vnet-${local.env_prefix}-${local.service}-${local.location_abbr}"

    # Subnets
    session_hosts_subnet = "snet-${local.env_prefix}-${local.service}-${local.location_abbr}-hosts"

    # Network Security Groups
    session_hosts_nsg = "nsg-${local.env_prefix}-${local.service}-${local.location_abbr}-hosts"

    # AVD Core Resources (added missing service component)
    host_pool         = "vdpool-${local.env_prefix}-${local.service}-${local.location_abbr}"
    workspace         = "vdws-${local.env_prefix}-${local.service}-${local.location_abbr}"
    application_group = "vdag-${local.env_prefix}-${local.service}-${local.location_abbr}"
    scaling_plan      = "vdscale-${local.env_prefix}-${local.service}-${local.location_abbr}"


    # Storage Accounts
    profiles_storage = "st${local.env_prefix}${local.service}prof${local.random_suffix}"

    # Key Vault
    key_vault = "kv-${local.env_prefix}-${local.service}-${local.random_suffix}"

    # User Assigned Identity
    managed_identity = "id-${local.env_prefix}-${local.service}-umi-${local.location_abbr}"

    # Recovery Services Vault
    recovery_vault = "rsv-${local.env_prefix}-${local.service}-${local.location_abbr}"

    # Shared Image Gallery (fixed: use dashes instead of underscores)
    shared_image_gallery = "sig-${local.env_prefix}-${local.service}-${local.location_abbr}"


    # Private Endpoints
    kv_private_endpoint      = "pe-kv-${local.env_prefix}-${local.service}-${local.location_abbr}"
    storage_private_endpoint = "pe-st-${local.env_prefix}-${local.service}-${local.location_abbr}"

    # Load Balancer (if needed)
    load_balancer = "lb-${local.env_prefix}-${local.service}-${local.location_abbr}"

    # Application Security Groups
    session_hosts_asg = "asg-${local.env_prefix}-${local.service}-${local.location_abbr}-hosts"

    # Log Analytics Workspace (dedicated for AVD)
    log_analytics_workspace = "log${local.env_prefix}${local.service}${local.location_abbr}"
  }

  # Standard tags for AVD resources
  avd_tags = merge(var.default_tags, {
    Workload = "Azure Virtual Desktop"
  })
}

# Random string for unique resource naming in AVD
resource "random_string" "avd_naming" {
  length  = 6
  upper   = false
  special = false
}

# Validation for storage account name length (max 24 characters)
locals {
  storage_account_names = {
    profiles = length(local.avd_names.profiles_storage) <= 24 ? local.avd_names.profiles_storage : substr(local.avd_names.profiles_storage, 0, 24)
  }
}
