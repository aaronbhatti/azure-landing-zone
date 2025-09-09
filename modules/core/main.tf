# Core Module - Azure Landing Zone governance using ALZ Pattern


# Get current client configuration for tenant information
data "azurerm_client_config" "current" {
  provider = azurerm.management
}

# Get azapi client config for ALZ integration
data "azapi_client_config" "current" {}

resource "modtm_telemetry" "core" {
  count = var.enable_telemetry ? 1 : 0

  tags = merge(var.default_tags, {
    Workload = "Management"
  })
}

# Custom architecture definition is loaded from modules/core/lib/custom.alz_architecture_definition.json
# The ALZ provider automatically loads it via the library_references configuration in terraform.tf

# ALZ Management Groups & Policies using AVM Pattern Module
module "alz" {
  source  = "Azure/avm-ptn-alz/azurerm"
  version = "~> 0.13.0"

  # Required attributes for ALZ pattern  
  architecture_name  = "custom"
  parent_resource_id = var.core_config.management_group_parent_id != null ? var.core_config.management_group_parent_id : data.azurerm_client_config.current.tenant_id
  location           = var.location

  # Subscription Placement - place subscriptions in custom management groups
  # Conditionally add AVD and infrastructure workload placements when they have unique subscription IDs
  subscription_placement = merge(
    local.unique_subscription_placement,

    # Only add AVD subscription if it has a different subscription ID from core subscriptions
    var.avd_subscription_id != null &&
    var.avd_subscription_id != var.management_subscription_id &&
    var.avd_subscription_id != var.connectivity_subscription_id &&
    var.avd_subscription_id != var.identity_subscription_id ? {
      "avd-workload" = {
        management_group_name = "avd"
        subscription_id       = var.avd_subscription_id
      }
    } : {},

    # Only add infrastructure subscription if it has a different subscription ID from core subscriptions
    var.infra_subscription_id != null &&
    var.infra_subscription_id != var.management_subscription_id &&
    var.infra_subscription_id != var.connectivity_subscription_id &&
    var.infra_subscription_id != var.identity_subscription_id &&
    var.infra_subscription_id != var.avd_subscription_id ? {
      "infrastructure-workload" = {
        management_group_name = "infrastructure"
        subscription_id       = var.infra_subscription_id
      }
    } : {}
  )


  # Enhanced archetype configuration is handled via policy_assignments_to_modify and defaults

  # Policy assignments for connectivity (customize as needed)
  policy_assignments_to_modify = {
    connectivity = {
      policy_assignments = {
        # As we don't have a DDOS protection plan, we need to disable this policy
        # to prevent a modify action from failing.
        Enable-DDoS-VNET = {
          enforcement_mode = "DoNotEnforce"
        }
      }
    }
  }


  enable_telemetry = var.enable_telemetry
}
