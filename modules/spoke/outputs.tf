# Generic Landing Zone Spoke Outputs

output "resource_group" {
  description = "The spoke resource group"
  value       = module.spoke_resource_group.resource
}

output "resource_group_id" {
  description = "The ID of the spoke resource group"
  value       = module.spoke_resource_group.resource.id
}

output "resource_group_name" {
  description = "The name of the spoke resource group"
  value       = module.spoke_resource_group.resource.name
}

output "virtual_network" {
  description = "The spoke virtual network"
  value       = var.spoke_config.virtual_network != null ? module.spoke_virtual_network[0].resource : null
}

output "virtual_network_id" {
  description = "The ID of the spoke virtual network"
  value       = var.spoke_config.virtual_network != null ? module.spoke_virtual_network[0].resource.id : null
}

output "subnets" {
  description = "The spoke subnets"
  value       = var.spoke_config.virtual_network != null ? module.spoke_virtual_network[0].subnets : null
}

output "network_security_group" {
  description = "The spoke network security group"
  value       = var.spoke_config.virtual_network != null ? azurerm_network_security_group.spoke[0] : null
}

output "route_table" {
  description = "The spoke route table"
  value       = var.spoke_config.virtual_network != null ? module.spoke_route_table[0].resource : null
}

output "storage_account" {
  description = "The spoke storage account"
  value       = var.spoke_config.enable_storage ? module.spoke_storage[0].resource : null
  sensitive   = true
}

output "recovery_services_vault" {
  description = "The spoke recovery services vault"
  value       = var.spoke_config.enable_backup ? module.spoke_recovery_services_vault[0].resource : null
}

output "key_vault" {
  description = "The spoke key vault"
  value       = var.spoke_config.enable_key_vault ? module.spoke_key_vault[0].resource_id : null
  sensitive   = true
}

output "virtual_machines" {
  description = "The spoke virtual machines"
  value = var.spoke_config.deploy_virtual_machines ? {
    for k, vm in module.spoke_virtual_machines : k => {
      id                 = vm.virtual_machine.id
      name               = vm.virtual_machine.name
      private_ip_address = vm.virtual_machine.private_ip_address
      public_ip_address  = vm.virtual_machine.public_ip_address
    }
  } : {}
}

# Availability sets removed - using availability zones for better resilience
# VMs are automatically distributed across zones 1, 2, and 3

# Role-specific outputs for backward compatibility
output "domain_controllers" {
  description = "Domain controllers information (for identity workloads)"
  value = var.workload_role == "identity" && var.spoke_config.deploy_virtual_machines ? {
    for k, vm in module.spoke_virtual_machines : k => {
      id                 = vm.virtual_machine.id
      name               = vm.virtual_machine.name
      private_ip_address = vm.virtual_machine.private_ip_address
      computer_name      = vm.virtual_machine.computer_name
    }
    if contains(keys(var.spoke_config.virtual_machines), "dc") || contains(keys(var.spoke_config.virtual_machines), "domain_controller")
  } : {}
  sensitive = true
}

output "identity_outputs" {
  description = "Identity-specific outputs (when workload_role is identity)"
  value = var.workload_role == "identity" ? {
    domain_controllers = var.spoke_config.deploy_virtual_machines ? {
      for k, vm in module.spoke_virtual_machines : k => {
        id                 = vm.virtual_machine.id
        name               = vm.virtual_machine.name
        private_ip_address = vm.virtual_machine.private_ip_address
        computer_name      = vm.virtual_machine.computer_name
      }
      if contains(keys(var.spoke_config.virtual_machines), "dc") || contains(keys(var.spoke_config.virtual_machines), "domain_controller")
    } : {}
    key_vault_id = var.spoke_config.enable_key_vault ? module.spoke_key_vault[0].resource_id : null
  } : null
  sensitive = true
}

output "infra_outputs" {
  description = "Infrastructure-specific outputs (when workload_role is infra)"
  value = var.workload_role == "infra" ? {
    application_servers = var.spoke_config.deploy_virtual_machines ? {
      for k, vm in module.spoke_virtual_machines : k => {
        id                 = vm.virtual_machine.id
        name               = vm.virtual_machine.name
        private_ip_address = vm.virtual_machine.private_ip_address
      }
      if contains(keys(var.spoke_config.virtual_machines), "app") || contains(keys(var.spoke_config.virtual_machines), "application_server")
    } : {}
  } : null
}

# Diagnostic outputs
output "diagnostic_settings" {
  description = "Diagnostic settings configured for the spoke"
  value = {
    nsg_diagnostics     = var.spoke_config.virtual_network != null && var.log_analytics_workspace_id != null ? azurerm_monitor_diagnostic_setting.spoke_nsg_diagnostics[0] : null
    storage_diagnostics = var.spoke_config.enable_storage ? azurerm_monitor_diagnostic_setting.spoke_storage_diagnostics[0] : null
  }
}

# Naming outputs for reference
output "naming" {
  description = "Naming convention outputs"
  value = {
    resource_names      = local.spoke_names
    role_specific_names = local.role_specific_names
    storage_names       = local.storage_account_names
  }
}

# Tags output
output "tags" {
  description = "Tags applied to resources"
  value       = local.spoke_tags
}