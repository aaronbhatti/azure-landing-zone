# Core Outputs
output "core" {
  description = "ALZ Core governance information (management groups, policies, etc.)"
  value = var.core_config.enabled ? {
    # Management Groups & Policies
    management_groups  = module.core[0].management_groups
    policy_assignments = module.core[0].policy_assignments
    policy_definitions = module.core[0].policy_definitions
    role_assignments   = module.core[0].role_assignments
  } : null
}

# Management Outputs (ALZ Management Resources)
output "management" {
  description = "ALZ Management resources information (Log Analytics, Automation Account, etc.)"
  value = var.management_config.enabled ? {
    # Management Resources
    resource_group_id                 = module.management[0].resource_group_id
    resource_group_name               = module.management[0].resource_group_name
    log_analytics_workspace_id        = module.management[0].log_analytics_workspace_id
    log_analytics_workspace_name      = module.management[0].log_analytics_workspace_name
    automation_account_id             = module.management[0].automation_account_id
    automation_account_name           = module.management[0].automation_account_name
    user_assigned_managed_identity_id = module.management[0].user_assigned_managed_identity_id
  } : null
}

# Connectivity Outputs
output "connectivity" {
  description = "Connectivity module outputs"
  value = var.connectivity_config.enabled ? {
    resource_group_id        = module.connectivity[0].resource_group_id
    resource_group_name      = module.connectivity[0].resource_group_name
    hub_virtual_network_id   = module.connectivity[0].hub_virtual_network_id
    hub_virtual_network_name = module.connectivity[0].hub_virtual_network_name
    firewall_id              = module.connectivity[0].firewall_id
    firewall_private_ip      = module.connectivity[0].firewall_private_ip
    vpn_gateway_id           = module.connectivity[0].vpn_gateway_id
  } : null
}

# Identity Outputs (when enabled)
output "identity" {
  description = "Identity module outputs"
  value = var.identity_subscription_id != null && var.identity_config != null && var.identity_config.enabled ? {
    resource_group_id   = module.identity[0].resource_group_id
    resource_group_name = module.identity[0].resource_group_name
    domain_controllers  = module.identity[0].domain_controllers
  } : null
  sensitive = true
}

# AVD Outputs (when enabled)
output "avd" {
  description = "Azure Virtual Desktop module outputs"
  value = var.avd_config.enabled ? {
    resource_group_id   = module.avd[0].resource_group_id
    resource_group_name = module.avd[0].resource_group_name
    workspace           = module.avd[0].virtual_desktop_workspace
    host_pool           = module.avd[0].virtual_desktop_host_pool
    application_group   = module.avd[0].virtual_desktop_application_group
    insights            = module.avd[0].avd_insights
    virtual_network_id  = module.avd[0].virtual_network_id
    peering_connections = module.avd[0].peering_connections
  } : null
  sensitive = true
}
# Azure Image Builder Outputs (when enabled)
output "aib" {
  description = "Azure Image Builder module outputs"
  value = var.aib_config.enabled ? {
    resource_group         = module.aib[0].resource_group
    managed_identity       = module.aib[0].managed_identity
    compute_gallery        = module.aib[0].compute_gallery
    image_templates        = module.aib[0].image_templates
    custom_role_definition = module.aib[0].custom_role_definition
    script_uris            = module.aib[0].script_uris
    build_commands         = module.aib[0].build_commands
  } : null
  sensitive = true
}

# Infrastructure Outputs
output "infra" {
  description = "Infrastructure landing zone outputs"
  value = var.infra_config.enabled ? {
    resource_group_id   = module.infrastructure[0].resource_group_id
    resource_group_name = module.infrastructure[0].resource_group_name
    virtual_network     = module.infrastructure[0].virtual_network
  } : null
}

# Summary Output
output "landing_zone_summary" {
  description = "Summary of the deployed Azure Landing Zone"
  value = {
    org_name    = var.org_name
    environment = var.environment
    location    = var.location
    subscriptions = {
      management     = var.management_subscription_id
      connectivity   = var.connectivity_subscription_id
      identity       = var.identity_subscription_id
      infrastructure = var.infra_subscription_id
      avd            = var.avd_subscription_id
      aib            = var.aib_subscription_id
    }
    infra_enabled        = var.infra_config != null
    deployment_timestamp = timestamp()
  }
}
