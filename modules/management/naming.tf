# Management Module - Naming Convention
# This file defines the naming standards for all management resources

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
  random_suffix = random_string.management_naming.result

  # Service identifier for management resources
  service = "mgmt"

  # Resource naming patterns for management module
  management_names = {
    # Resource Group
    resource_group = "rg-${local.env_prefix}-${local.service}-${local.location_abbr}-service"

    # Log Analytics Workspace (no dashes in name)
    log_analytics_workspace = "log${local.env_prefix}${local.service}${local.location_abbr}"

    # Automation Account
    automation_account = "aa-${local.env_prefix}-${local.service}-${local.location_abbr}"

    # Storage Account (for runbook scripts, etc.)
    storage_account = "st${local.env_prefix}${local.service}${local.random_suffix}"

    # Key Vault (for automation secrets)
    key_vault = "kv-${local.env_prefix}-${local.service}-${local.random_suffix}"

    # User Assigned Identity
    managed_identity = "id-${local.env_prefix}-${local.service}-umi-${local.location_abbr}"

    # Application Insights
    application_insights = "appi-${local.env_prefix}-${local.service}-${local.location_abbr}"

    # Action Groups
    action_group = "ag-${local.env_prefix}-${local.service}-${local.location_abbr}"

    # Dashboards
    dashboard = "dash-${local.env_prefix}-${local.service}-${local.location_abbr}"

    # Data Collection Rules
    dcr_vm_insights = "dcr-${local.env_prefix}-${local.service}-vminsights-${local.location_abbr}"

    # Private Endpoints
    kv_private_endpoint      = "pe-kv-${local.env_prefix}-${local.service}-${local.location_abbr}"
    storage_private_endpoint = "pe-st-${local.env_prefix}-${local.service}-${local.location_abbr}"

    # Budget
    budget = "budget-${local.env_prefix}-${local.service}"

    # Policy Assignments (if managed here)
    policy_assignment_prefix = "pa-${local.env_prefix}-${local.service}"
  }

  # Standard tags for management resources
  management_tags = merge(var.default_tags, {
    Workload = "Management"
  })
}

# Random string for unique resource naming in management
resource "random_string" "management_naming" {
  length  = 6
  upper   = false
  special = false
}

# Validation for storage account name length (max 24 characters)
locals {
  storage_account_name = length(local.management_names.storage_account) <= 24 ? local.management_names.storage_account : substr(local.management_names.storage_account, 0, 24)
}
