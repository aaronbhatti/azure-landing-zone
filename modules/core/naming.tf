# Core Module - Naming Conventions
# Standardized naming for ALZ core governance components

# Environment and location processing
locals {
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

  # Core service identifier
  service = "core"

  # Random suffix for unique resources (when needed)
  random_suffix = lower(random_string.core_naming.result)

  # Unique subscription placement - avoid placing same subscription in multiple management groups
  unique_subscriptions = toset(compact([
    var.connectivity_subscription_id,
    var.management_subscription_id,
    var.identity_subscription_id
  ]))

  # Create subscription placement map with unique subscriptions only
  subscription_placement_map = {
    for sub_id in local.unique_subscriptions : sub_id => {
      connectivity = sub_id == var.connectivity_subscription_id ? "connectivity" : null
      management   = sub_id == var.management_subscription_id ? "management" : null
      identity     = sub_id == var.identity_subscription_id ? "identity" : null
    }
  }

  # Final subscription placement - place each subscription only once, prioritizing management > connectivity > identity
  unique_subscription_placement = {
    for sub_id in local.unique_subscriptions : (
      local.subscription_placement_map[sub_id].management != null ? "management-${sub_id}" :
      local.subscription_placement_map[sub_id].connectivity != null ? "connectivity-${sub_id}" :
      "identity-${sub_id}"
      ) => {
      management_group_name = (
        local.subscription_placement_map[sub_id].management != null ? "management" :
        local.subscription_placement_map[sub_id].connectivity != null ? "connectivity" :
        "identity"
      )
      subscription_id = sub_id
    }
  }
}

# Random string for naming uniqueness
resource "random_string" "core_naming" {
  length  = 4
  lower   = true
  upper   = false
  special = false
  numeric = true
}

# Standardized core resource names
locals {
  core_names = {
    # Resource groups
    resource_group = "rg-${local.service}-${local.env_prefix}-${local.location_abbr}"

    # Log Analytics workspace (if deployed at core level)
    log_analytics_workspace = "law-${local.service}-${local.env_prefix}-${local.location_abbr}"

    # Automation account (if deployed at core level)  
    automation_account = "aa-${local.service}-${local.env_prefix}-${local.location_abbr}"

    # Storage account for core artifacts
    storage_account = replace(lower("st${local.service}${local.env_prefix}${local.location_abbr}${local.random_suffix}"), "[^a-z0-9]", "")

    # Key vault for core secrets
    key_vault = "kv-${local.service}-${local.env_prefix}-${local.location_abbr}-${local.random_suffix}"

    # User assigned managed identity
    managed_identity = "id-${local.service}-${local.env_prefix}-${local.location_abbr}"
  }
}