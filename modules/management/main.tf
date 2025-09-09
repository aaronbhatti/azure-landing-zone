# Management Module - ALZ management resources


resource "modtm_telemetry" "management" {
  count = var.enable_telemetry ? 1 : 0

  tags = local.management_tags
}

# ALZ Management Resources using AVM Pattern Module
module "alz_management" {
  source  = "Azure/avm-ptn-alz-management/azurerm"
  version = "~> 0.9.0"

  providers = {
    azurerm = azurerm.management
  }

  # Required Configuration
  resource_group_name = local.management_names.resource_group
  location            = var.location

  # Log Analytics Workspace Configuration (ALZ creates it)
  log_analytics_workspace_name = local.management_names.log_analytics_workspace

  # Automation Account Configuration (conditional)
  automation_account_name                    = var.enable_automation_account ? local.management_names.automation_account : null
  linked_automation_account_creation_enabled = var.enable_automation_account

  # Data Collection Rules configuration for ALZ policy dependencies
  data_collection_rules = {
    change_tracking = {
      name    = "dcr-change-tracking"
      enabled = true
    }
    vm_insights = {
      name    = "dcr-vm-insights"
      enabled = true
    }
    defender_sql = {
      name                                                   = "dcr-defender-sql"
      enabled                                                = true
      enable_collection_of_sql_queries_for_security_research = false
    }
  }

  # Sentinel configuration - required for v0.9.0 (disabled by default)
  sentinel_onboarding = {}

  enable_telemetry = var.enable_telemetry

  # Tags
  tags = local.management_tags
}