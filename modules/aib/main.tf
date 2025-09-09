# Azure Image Builder Module - Modern AVM Implementation
# This module creates a complete Azure Image Builder environment with:
# - Shared Image Gallery using AVM module
# - Storage Account for scripts using AVM module  
# - User Assigned Managed Identity with proper RBAC
# - Image Template with comprehensive AVD optimizations


resource "modtm_telemetry" "aib" {
  count = var.enable_telemetry ? 1 : 0

  tags = merge(var.default_tags, {
    Workload = "Azure Image Builder"
  })
}

# Resource Group for AIB resources using AVM module
module "aib_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = ">= 0.1.0, < 1.0.0"

  name     = local.resource_names.resource_group
  location = var.location

  enable_telemetry = var.enable_telemetry

  tags = merge(var.default_tags, {
    Workload = "Azure Image Builder"
  })
}

# User Assigned Managed Identity for AIB
resource "azurerm_user_assigned_identity" "aib" {
  name                = local.resource_names.managed_identity
  resource_group_name = module.aib_resource_group.resource.name
  location            = module.aib_resource_group.resource.location

  tags = merge(var.default_tags, {
    Workload = "Azure Image Builder"
  })
}

# Custom role definition for Azure Image Builder
resource "azurerm_role_definition" "aib" {
  name        = "[${var.org_name}] Azure Image Builder Role"
  scope       = data.azurerm_subscription.current.id
  description = "Azure Image Builder AVD"

  permissions {
    actions = [
      "Microsoft.Authorization/*/read",
      "Microsoft.Compute/images/write",
      "Microsoft.Compute/images/read",
      "Microsoft.Compute/images/delete",
      "Microsoft.Compute/galleries/read",
      "Microsoft.Compute/galleries/images/read",
      "Microsoft.Compute/galleries/images/versions/read",
      "Microsoft.Compute/galleries/images/versions/write",
      "Microsoft.Storage/storageAccounts/blobServices/containers/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/write",
      "Microsoft.Storage/storageAccounts/blobServices/read",
      "Microsoft.ContainerInstance/containerGroups/read",
      "Microsoft.ContainerInstance/containerGroups/write",
      "Microsoft.ContainerInstance/containerGroups/start/action",
      "Microsoft.ManagedIdentity/userAssignedIdentities/*/read",
      "Microsoft.ManagedIdentity/userAssignedIdentities/*/assign/action",
      "Microsoft.Resources/deployments/*",
      "Microsoft.Resources/deploymentScripts/read",
      "Microsoft.Resources/deploymentScripts/write",
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.VirtualMachineImages/imageTemplates/run/action",
      "Microsoft.VirtualMachineImages/imageTemplates/read",
      "Microsoft.Network/virtualNetworks/read",
      "Microsoft.Network/virtualNetworks/subnets/join/action"
    ]
    not_actions = []
  }

  assignable_scopes = [
    data.azurerm_subscription.current.id,
    module.aib_resource_group.resource.id,
    module.aib_storage.resource_id
  ]
}

# Role assignment for AIB managed identity
resource "azurerm_role_assignment" "aib" {
  scope              = module.aib_resource_group.resource.id
  role_definition_id = azurerm_role_definition.aib.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.aib.principal_id
}

# Storage Account for scripts using AVM module
module "aib_storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "~> 0.6.4"

  providers = {
    azurerm = azurerm
  }

  name                = local.resource_names.storage_account
  resource_group_name = module.aib_resource_group.resource.name
  location            = module.aib_resource_group.resource.location

  # Storage configuration
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = true
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true

  # Enable system assigned identity for storage
  managed_identities = {
    system_assigned = true
  }

  # Network access rules
  network_rules = var.aib_config.enable_private_endpoints ? {
    default_action = "Deny"
    bypass         = ["AzureServices", "Metrics", "Logging"]
    ip_rules       = var.allow_list_ip
  } : null

  # Blob containers for scripts
  containers = {
    scripts = {
      name                  = local.resource_names.scripts_container
      container_access_type = "blob"
    }
    logs = {
      name                  = local.resource_names.logs_container
      container_access_type = "private"
    }
  }

  # File shares for application deployment
  shares = var.aib_config.enable_file_share ? {
    apps = {
      name  = "apps"
      quota = var.aib_config.file_share_quota_gb
    }
    deploymentshare = {
      name  = "deploymentshare"
      quota = var.aib_config.file_share_quota_gb
    }
  } : {}

  # Private endpoints if enabled
  private_endpoints = var.aib_config.enable_private_endpoints ? {
    blob = {
      name                            = "pe-${local.resource_names.storage_account}-blob"
      subnet_resource_id              = var.private_endpoint_subnet_id
      private_service_connection_name = "psc-${local.resource_names.storage_account}-blob"
      network_interface_name          = "nic-pe-${local.resource_names.storage_account}-blob"
      subresource_name                = "blob"

      private_dns_zone_group = var.private_dns_zone_blob_id != null ? {
        private_dns_zone_group_name = "dns-${local.resource_names.storage_account}-blob"
        private_dns_zone_ids        = [var.private_dns_zone_blob_id]
      } : null
    }
    file = var.aib_config.enable_file_share ? {
      name                            = "pe-${local.resource_names.storage_account}-file"
      subnet_resource_id              = var.private_endpoint_subnet_id
      private_service_connection_name = "psc-${local.resource_names.storage_account}-file"
      network_interface_name          = "nic-pe-${local.resource_names.storage_account}-file"
      subresource_name                = "file"

      private_dns_zone_group = var.private_dns_zone_file_id != null ? {
        private_dns_zone_group_name = "dns-${local.resource_names.storage_account}-file"
        private_dns_zone_ids        = [var.private_dns_zone_file_id]
      } : null
    } : null
  } : {}

  tags = merge(var.default_tags, {
    Workload = "Azure Image Builder"
  })

  depends_on = [module.aib_resource_group.resource]
}

# Role assignment for AIB to access storage
resource "azurerm_role_assignment" "aib_storage" {
  principal_id         = azurerm_user_assigned_identity.aib.principal_id
  role_definition_name = "Storage Blob Data Reader"
  scope                = module.aib_storage.resource_id
}

# Network Contributor role assignment for AVD network resource group (if provided)
resource "azurerm_role_assignment" "aib_network_rg" {
  count                = var.avd_network_resource_group_id != null ? 1 : 0
  principal_id         = azurerm_user_assigned_identity.aib.principal_id
  role_definition_name = "Network Contributor"
  scope                = var.avd_network_resource_group_id
}

# Network Contributor role assignment for AVD virtual network (if provided)
resource "azurerm_role_assignment" "aib_vnet" {
  count                = var.avd_vnet_id != null ? 1 : 0
  principal_id         = azurerm_user_assigned_identity.aib.principal_id
  role_definition_name = "Network Contributor"
  scope                = var.avd_vnet_id
}

# Shared Image Gallery using AVM module
module "compute_gallery" {
  source  = "Azure/avm-res-compute-gallery/azurerm"
  version = "~> 0.2.0"

  providers = {
    azurerm = azurerm
  }

  name                = local.resource_names.compute_gallery
  resource_group_name = module.aib_resource_group.resource.name
  location            = module.aib_resource_group.resource.location

  description = "Shared Image Gallery for ${var.org_name} custom images"

  # Gallery images configuration
  shared_image_definitions = {
    for image_key, image_config in var.aib_config.images : image_key => {
      name                              = "${image_config.name}-${local.env_prefix}"
      description                       = image_config.description
      os_type                           = image_config.os_type
      hyper_v_generation                = image_config.hyper_v_generation
      trusted_launch_supported          = image_config.trusted_launch_supported
      disk_controller_type_nvme_enabled = image_config.enable_nvme_disk_controller

      identifier = {
        publisher = image_config.publisher
        offer     = image_config.offer
        sku       = image_config.sku
      }

      tags = merge(var.default_tags, {
        Workload  = "Azure Image Builder"
        ImageType = image_config.name
      })
    }
  }

  tags = merge(var.default_tags, {
    Workload = "Azure Image Builder"
  })

  depends_on = [module.aib_resource_group.resource]
}

# Generate PowerShell script from template using template_file data source
data "template_file" "install_scripts" {
  for_each = var.aib_config.images

  template = file("${path.module}/scripts/aib_install_script.ps1.tftpl")
  vars = {
    script_storage_name = module.aib_storage.resource.name
    script_share_name   = "deploymentshare"
    storage_account_key = module.aib_storage.resource.primary_access_key
  }
}

# Ensure scripts directory exists
resource "local_file" "scripts_directory" {
  content  = ""
  filename = "${path.module}/scripts/generated/.gitkeep"
}

# Save generated scripts
resource "local_file" "generated_scripts" {
  for_each = var.aib_config.images

  content  = data.template_file.install_scripts[each.key].rendered
  filename = "${path.module}/scripts/generated/${each.key}_install_script.ps1"

  depends_on = [local_file.scripts_directory]
}

# Upload scripts to blob storage
resource "azurerm_storage_blob" "install_scripts" {
  for_each = var.aib_config.images

  name                   = "${each.key}_install_script.ps1"
  storage_account_name   = module.aib_storage.resource.name
  storage_container_name = local.resource_names.scripts_container
  type                   = "Block"
  source                 = local_file.generated_scripts[each.key].filename

  depends_on = [module.aib_storage]
}

# Get script blob information for checksum
data "azurerm_storage_blob" "script_blobs" {
  for_each = var.aib_config.images

  name                   = azurerm_storage_blob.install_scripts[each.key].name
  storage_account_name   = azurerm_storage_blob.install_scripts[each.key].storage_account_name
  storage_container_name = azurerm_storage_blob.install_scripts[each.key].storage_container_name
}

# Wait for role assignments to propagate
resource "time_sleep" "rbac_propagation" {
  depends_on = [
    azurerm_role_assignment.aib,
    azurerm_role_assignment.aib_storage,
    azurerm_role_assignment.aib_network_rg,
    azurerm_role_assignment.aib_vnet
  ]
  create_duration = "60s"
}

# Azure Image Builder Template using ARM template
resource "azurerm_resource_group_template_deployment" "image_templates" {
  for_each = var.aib_config.images

  name                = "${each.key}-template-${local.env_prefix}-${random_string.deployment_suffix.result}"
  resource_group_name = module.aib_resource_group.resource.name
  deployment_mode     = "Incremental"

  parameters_content = jsonencode({
    "imageTemplateName" = {
      value = "${each.key}-${local.env_prefix}"
    }
    "api-version" = {
      value = local.api_version
    }
    "svclocation" = {
      value = var.location
    }
  })

  template_content = <<TEMPLATE
{
    "$schema": "http://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "imageTemplateName": {
            "type": "string"
        },
        "api-version": {
            "type": "string"
        },
        "svclocation": {
            "type": "string"
        }
    },
    "variables": {},
    "resources": [
        {
            "name": "[parameters('imageTemplateName')]",
            "type": "Microsoft.VirtualMachineImages/imageTemplates",
            "apiVersion": "[parameters('api-version')]",
            "location": "[parameters('svclocation')]",
            "dependsOn": [],
            "tags": {
                "Environment": "${local.env_prefix}",
                "Project": "Azure Virtual Desktop",
                "AVD_IMAGE_TEMPLATE": "AVD_IMAGE_TEMPLATE",
                "userIdentity": "enabled",
                "ImageTemplateResourceName": "[parameters('imageTemplateName')]",
                "ImageTemplateType": "CustomVmImage",
                "SourceImageType": "PlatformImage"
            },
            "identity": {
                "type": "UserAssigned",
                "userAssignedIdentities": {
                    "${azurerm_user_assigned_identity.aib.id}": {}
                }
            },
            "properties": {
                "buildTimeoutInMinutes": ${each.value.build_timeout_minutes},
                "stagingResourceGroup": "${data.azurerm_subscription.current.id}/resourceGroups/rg-${local.env_prefix}-avd-${local.location_abbr}-imagebuilder-staging",
                "vmProfile": {
                    "vmSize": "${each.value.vm_size}",
                    "osDiskSizeGB": ${each.value.os_disk_size_gb}${var.build_subnet_id != null ? ",\n                    \"vnetConfig\": {\n                        \"subnetId\": \"${var.build_subnet_id}\"\n                    }" : ""}
                },
                "source": {
                    "type": "PlatformImage",
                    "publisher": "${each.value.publisher}",
                    "offer": "${each.value.offer}",
                    "sku": "${each.value.sku}",
                    "version": "${each.value.version}"
                },
                "customize": ${replace(replace(jsonencode([
  for customization in local.default_customizations : {
    name           = customization.name
    type           = customization.type
    searchCriteria = try(customization.searchCriteria, null)
    filters        = try(customization.filters, null)
    updateLimit    = try(customization.updateLimit, null)
    restartTimeout = try(customization.restartTimeout, null)
    runAsSystem    = try(customization.runAsSystem, null)
    runElevated    = try(customization.runElevated, null)
    scriptUri      = try(customization.scriptUri, null)
    sha256Checksum = try(customization.sha256Checksum, null)
    destination    = try(customization.destination, null)
    sourceUri      = try(customization.sourceUri, null)
    inline         = try(customization.inline, null)
  }
]), "\"CUSTOM_SCRIPT_PLACEHOLDER\"", "\"https://${module.aib_storage.resource.name}.blob.core.windows.net/scripts/${azurerm_storage_blob.install_scripts[each.key].name}\""), "\"CUSTOM_SCRIPT_CHECKSUM_PLACEHOLDER\"", "\"${data.azurerm_storage_blob.script_blobs[each.key].content_md5}\"")},
                "distribute": [
                    {
                        "type": "SharedImage",
                        "galleryImageId": "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${module.aib_resource_group.resource.name}/providers/Microsoft.Compute/galleries/${local.resource_names.compute_gallery}/images/${each.value.name}-${local.env_prefix}",
                        "runOutputName": "${each.key}-${local.env_prefix}",
                        "artifactTags": {
                            "source": "azureVmImageBuilder",
                            "baseosimg": "windows11"
                        },
                        "replicationRegions": [${join(",", formatlist("\"%s\"", var.aib_config.replication_regions))}]
                    }
                ]
            }
        }
    ]
}
TEMPLATE

depends_on = [
  time_sleep.rbac_propagation,
  module.compute_gallery,
  azurerm_storage_blob.install_scripts
]

tags = merge(var.default_tags, {
  Workload          = "Azure Image Builder"
  Environment       = local.env_prefix
  Application       = "Azure Virtual Desktop"
  ImageTemplateType = "CustomVmImage"
  SourceImageType   = "PlatformImage"
})

lifecycle {
  ignore_changes = [
    template_content,
    parameters_content
  ]
}
}

# Random string for deployment names
resource "random_string" "deployment_suffix" {
  length  = 4
  upper   = false
  special = false
}

# Data sources
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}
