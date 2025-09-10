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

  # Sentinel configuration - configurable via variables (disabled by default)
  # null = disabled, {} = enabled with defaults, {...} = enabled with custom values
  sentinel_onboarding = var.sentinel_config.enabled ? (
    var.sentinel_config.name == "default" && var.sentinel_config.customer_managed_key_enabled == false ? {} : {
      name                          = var.sentinel_config.name != "default" ? var.sentinel_config.name : null
      customer_managed_key_enabled  = var.sentinel_config.customer_managed_key_enabled != false ? var.sentinel_config.customer_managed_key_enabled : null
    }
  ) : null

  enable_telemetry = var.enable_telemetry

  # Tags
  tags = local.management_tags
}