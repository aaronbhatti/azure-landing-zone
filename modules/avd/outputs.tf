output "resource_group_id" {
  description = "The ID of the AVD resource group"
  value       = module.avd_resource_group.resource.id
}

output "resource_group_name" {
  description = "The name of the AVD resource group"
  value       = module.avd_resource_group.resource.name
}

output "virtual_desktop_workspace" {
  description = "Information about the AVD workspace"
  value = {
    id   = try(module.avd_management_plane.virtual_desktop_workspace_resource_id, null)
    name = try(module.avd_management_plane.virtual_desktop_workspace_name, null)
  }
}

output "virtual_desktop_host_pool" {
  description = "Information about the AVD host pool"
  value = {
    id                 = try(module.avd_management_plane.virtual_desktop_host_pool_resource_id, null)
    name               = try(module.avd_management_plane.virtual_desktop_host_pool_name, null)
    registration_token = try(module.avd_management_plane.virtual_desktop_host_pool_registration_token, null)
  }
  sensitive = true
}

output "virtual_desktop_application_group" {
  description = "Information about the AVD application group"
  value = {
    id   = try(module.avd_management_plane.virtual_desktop_application_group_resource_id, null)
    name = try(module.avd_management_plane.virtual_desktop_application_group_name, null)
  }
}

output "avd_insights" {
  description = "Information about AVD insights (if enabled)"
  value = var.avd_config.enable_insights && var.log_analytics_workspace_id != null ? {
    data_collection_rule_id = module.avd_insights[0].resource_id.id
  } : null
}

output "virtual_desktop_scaling_plan" {
  description = "Information about the AVD scaling plan (if enabled)"
  value = {
    id   = try(module.avd_management_plane.virtual_desktop_scaling_plan_resource_id, null)
    name = try(module.avd_management_plane.virtual_desktop_scaling_plan_name, null)
  }
}

output "virtual_network_id" {
  description = "The ID of the AVD virtual network (if created)"
  value       = var.avd_config.create_virtual_network ? module.avd_virtual_network[0].resource.id : null
}

output "virtual_network_name" {
  description = "The name of the AVD virtual network (if created)"
  value       = var.avd_config.create_virtual_network ? module.avd_virtual_network[0].resource.name : null
}

output "subnets" {
  description = "The AVD subnets (if virtual network was created)"
  value       = var.avd_config.create_virtual_network ? module.avd_virtual_network[0].subnets : null
}

output "peering_connections" {
  description = "Information about VNet peering connections (if created)"
  value = var.avd_config.create_virtual_network && var.avd_config.connect_to_hub ? {
    avd_to_hub = azurerm_virtual_network_peering.avd_to_hub[0].id
    hub_to_avd = azurerm_virtual_network_peering.hub_to_avd[0].id
  } : {}
}

output "network_security_group_id" {
  description = "The ID of the AVD network security group (if created)"
  value       = var.avd_config.create_virtual_network ? module.avd_nsg[0].resource.id : null
}

# FSLogix Storage Account Outputs
output "fslogix_storage_account" {
  description = "FSLogix storage account information"
  value = var.avd_config.fslogix.enabled ? {
    id                    = module.fslogix_storage_account[0].resource.id
    name                  = module.fslogix_storage_account[0].resource.name
    primary_access_key    = module.fslogix_storage_account[0].resource.primary_access_key
    primary_file_endpoint = module.fslogix_storage_account[0].resource.primary_file_endpoint
    primary_file_host     = module.fslogix_storage_account[0].resource.primary_file_host
    file_shares = {
      profiles_unc_path   = "\\\\${module.fslogix_storage_account[0].resource.primary_file_host}\\profiles"
      containers_unc_path = "\\\\${module.fslogix_storage_account[0].resource.primary_file_host}\\containers"
    }
  } : null
  sensitive = true
}

# Debug output to verify tags are being passed correctly
output "debug_avd_tags" {
  description = "Debug: Shows the tags being passed to AVD management plane module"
  value = {
    avd_tags                               = local.avd_tags
    virtual_desktop_host_pool_tags         = local.avd_tags
    virtual_desktop_workspace_tags         = local.avd_tags
    virtual_desktop_application_group_tags = local.avd_tags
    virtual_desktop_scaling_plan_tags      = local.avd_tags
  }
}
