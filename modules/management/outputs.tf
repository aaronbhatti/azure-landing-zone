# Management Module Outputs - ALZ Management Resources

output "resource_group_id" {
  description = "The ID of the management resource group"
  value       = try(module.alz_management.resource_group.id, null)
}

output "resource_group_name" {
  description = "The name of the management resource group"
  value       = try(module.alz_management.resource_group.name, null)
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = try(module.alz_management.log_analytics_workspace.id, null)
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace"
  value       = try(module.alz_management.log_analytics_workspace.name, null)
}

output "automation_account_id" {
  description = "The ID of the Automation Account"
  value       = try(module.alz_management.automation_account.id, null)
}

output "automation_account_name" {
  description = "The name of the Automation Account"
  value       = try(module.alz_management.automation_account.name, null)
}

output "user_assigned_managed_identity_id" {
  description = "The ID of the user assigned managed identity"
  value       = try(values(module.alz_management.user_assigned_identity_ids)[0], null)
}

output "user_assigned_managed_identity_name" {
  description = "The name of the user assigned managed identity"
  value       = try(keys(module.alz_management.user_assigned_identity_ids)[0], null)
}

# Additional outputs required for ALZ dependencies (following guide pattern)
output "data_collection_rule_ids" {
  description = "Data collection rule IDs for ALZ policy dependencies"
  value       = try(module.alz_management.data_collection_rule_ids, [])
}

output "resource_id" {
  description = "The resource ID of the management resource group"
  value       = try(module.alz_management.resource_group.id, null)
}

output "user_assigned_identity_ids" {
  description = "User assigned identity IDs for ALZ policy dependencies"
  value       = try(values(module.alz_management.user_assigned_identity_ids), [])
}

# Provide resource IDs for core module dependencies
output "management_resource_ids" {
  description = "Resource IDs for ALZ core dependencies"
  value = {
    log_analytics_workspace_id = try(module.alz_management.log_analytics_workspace.id, null)
    automation_account_id      = var.enable_automation_account ? try(module.alz_management.automation_account.id, null) : null
    resource_group_id          = try(module.alz_management.resource_group.id, null)
  }
}
