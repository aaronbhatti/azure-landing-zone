# Outputs for Azure Image Builder Module

output "resource_group" {
  description = "The Azure Image Builder resource group"
  value = {
    id       = module.aib_resource_group.resource.id
    name     = module.aib_resource_group.resource.name
    location = module.aib_resource_group.resource.location
  }
}

output "managed_identity" {
  description = "The User Assigned Managed Identity for Azure Image Builder"
  value = {
    id           = azurerm_user_assigned_identity.aib.id
    name         = azurerm_user_assigned_identity.aib.name
    principal_id = azurerm_user_assigned_identity.aib.principal_id
    client_id    = azurerm_user_assigned_identity.aib.client_id
  }
}

output "storage_account" {
  description = "The storage account used by Azure Image Builder"
  value = {
    id                    = module.aib_storage.resource_id
    name                  = module.aib_storage.resource.name
    primary_access_key    = try(module.aib_storage.resource.primary_access_key, null)
    primary_blob_endpoint = try(module.aib_storage.resource.primary_blob_endpoint, null)
  }
  sensitive = true
}

output "compute_gallery" {
  description = "The Shared Image Gallery (Compute Gallery)"
  value = {
    id     = try(module.compute_gallery.resource_id, module.compute_gallery.id, null)
    name   = try(module.compute_gallery.name, null)
    images = try(module.compute_gallery.images, {})
  }
}

output "image_templates" {
  description = "The Azure Image Builder image templates"
  value = {
    for k, v in azurerm_resource_group_template_deployment.image_templates : k => {
      id                  = v.id
      name                = v.name
      template_name       = "${k}-${var.environment}"
      resource_group_name = v.resource_group_name
    }
  }
}

output "custom_role_definition" {
  description = "The custom role definition for Azure Image Builder"
  value = {
    id    = azurerm_role_definition.aib.id
    name  = azurerm_role_definition.aib.name
    scope = azurerm_role_definition.aib.scope
  }
}

output "script_uris" {
  description = "URIs of the uploaded PowerShell scripts"
  value = {
    for k, v in azurerm_storage_blob.install_scripts : k =>
    "https://${module.aib_storage.resource.name}.blob.core.windows.net/scripts/${v.name}"
  }
}

# Output image template build commands for reference
output "build_commands" {
  description = "Azure CLI commands to trigger image builds"
  value = {
    for k, v in var.aib_config.images : k =>
    "az resource invoke-action --resource-group ${module.aib_resource_group.resource.name} --resource-type Microsoft.VirtualMachineImages/imageTemplates -n ${k}-${var.environment} --action Run"
  }
}
