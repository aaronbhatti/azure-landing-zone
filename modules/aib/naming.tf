# Naming convention for AIB module resources
locals {
  # Standardize environment processing
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
  service = "avd"

  # Resource naming following standard conventions (standardized environment usage)
  resource_names = {
    resource_group   = "rg-${local.env_prefix}-${local.service}-${local.location_abbr}-imagebuilder"
    managed_identity = "id-${local.env_prefix}-${local.service}-${local.location_abbr}-aib"
    compute_gallery  = "gal${local.env_prefix}${local.service}aib${local.location_abbr}"
    storage_account  = lower(substr(replace("st${local.env_prefix}${local.service}aib${local.location_abbr}${random_string.storage_suffix.result}", "-", ""), 0, 24))
    key_vault        = "kv-${local.env_prefix}-${local.service}-${local.location_abbr}-aib"

    # Storage container names (simplified)
    scripts_container = "scripts"
    logs_container    = "logs"
    apps_container    = "apps"
  }
}

# Random string for storage account name uniqueness
resource "random_string" "storage_suffix" {
  length  = 6
  upper   = false
  special = false
}