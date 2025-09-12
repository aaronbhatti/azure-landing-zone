# Generic Landing Zone Spoke Module
# Supports multiple workload roles: identity, infra, app, data, security, etc.


# Random string for unique naming
resource "random_string" "spoke_naming" {
  length  = 4
  special = false
  upper   = false
  numeric = true
  lower   = true
}

# Subscription validation
data "azurerm_client_config" "spoke" {
  provider = azurerm.spoke
}

# Local variables for better code organization
locals {
  # No locals needed - priorities are hardcoded in rules for simplicity
}

resource "terraform_data" "subscription_validation" {
  lifecycle {
    postcondition {
      condition     = data.azurerm_client_config.spoke.subscription_id == var.subscription_id
      error_message = "Provider subscription (${data.azurerm_client_config.spoke.subscription_id}) does not match required subscription (${var.subscription_id})"
    }
  }
}

# Telemetry
resource "modtm_telemetry" "spoke" {
  count = var.enable_telemetry ? 1 : 0
  tags  = local.spoke_tags
}

# Main Resource Group using AVM module  
module "spoke_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = ">= 0.1.0, < 1.0.0"

  providers = {
    azurerm = azurerm.spoke
  }

  name     = local.spoke_names.resource_group
  location = var.location

  enable_telemetry = var.enable_telemetry
  tags = merge(local.spoke_tags, {
    Purpose = "Network"
  })
}

# Note: Network resources are deployed to the main resource group (spoke_resource_group)
# No separate network resource group needed since they are now the same

# Storage Resource Group using AVM module
module "spoke_storage_resource_group" {
  count = var.spoke_config.enable_storage ? 1 : 0

  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = ">= 0.1.0, < 1.0.0"

  providers = {
    azurerm = azurerm.spoke
  }

  name     = local.spoke_names.storage_resource_group
  location = var.location

  enable_telemetry = var.enable_telemetry
  tags = merge(local.spoke_tags, {
    Purpose = "Storage"
  })
}

# Servers Resource Group using AVM module (for VMs)
module "spoke_servers_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = ">= 0.1.0, < 1.0.0"

  providers = {
    azurerm = azurerm.spoke
  }

  name     = local.spoke_names.servers_resource_group
  location = var.location

  enable_telemetry = var.enable_telemetry
  tags = merge(local.spoke_tags, {
    Purpose = "Servers"
  })
}

# Backup Resource Group using AVM module (for Recovery Services Vaults used for backup)
module "spoke_backup_resource_group" {
  count = var.spoke_config.enable_backup ? 1 : 0

  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = ">= 0.1.0, < 1.0.0"

  providers = {
    azurerm = azurerm.spoke
  }

  name     = local.spoke_names.backup_resource_group
  location = var.location

  enable_telemetry = var.enable_telemetry
  tags = merge(local.spoke_tags, {
    Purpose = "Backup"
  })
}

# Recovery Resource Group using AVM module (for Recovery Services Vaults used for ASR/DR)
module "spoke_recovery_resource_group" {
  count = var.spoke_config.enable_backup && var.environment == "dr" ? 1 : 0

  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = ">= 0.1.0, < 1.0.0"

  providers = {
    azurerm = azurerm.spoke
  }

  name     = local.spoke_names.recovery_resource_group
  location = var.location

  enable_telemetry = var.enable_telemetry
  tags = merge(local.spoke_tags, {
    Purpose = "Recovery"
  })
}

# Resolve DNS servers - replace "firewall" with actual firewall IP if provided
locals {
  resolved_dns_servers = var.dns_servers != null ? [
    for dns in var.dns_servers : dns == "firewall" && var.firewall_private_ip != null ? var.firewall_private_ip : dns
  ] : ["168.63.129.16"]
}

# Virtual Network using AVM module
module "spoke_virtual_network" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.10.0"

  providers = {
    azurerm = azurerm.spoke
  }

  name                = var.spoke_config.virtual_network.name != null ? var.spoke_config.virtual_network.name : local.spoke_names.virtual_network
  location            = module.spoke_resource_group.resource.location
  resource_group_name = module.spoke_resource_group.resource.name
  address_space       = var.spoke_config.virtual_network.address_space
  dns_servers = local.resolved_dns_servers != null ? {
    dns_servers = toset(local.resolved_dns_servers)
  } : null

  # Convert subnets to AVM format with consistent associations
  subnets = {
    for k, v in var.spoke_config.virtual_network.subnets : k => {
      name              = k
      address_prefixes  = v.address_prefixes
      service_endpoints = try(v.service_endpoints, null)
      delegations       = try(v.delegations, null)
      # Associate NSG and route table through the AVM module (using same syntax as AVD module)
      network_security_group_id = azurerm_network_security_group.spoke[0].id
      route_table = var.spoke_config.virtual_network != null ? {
        id = module.spoke_route_table[0].resource_id
      } : null
    }
  }

  enable_telemetry = var.enable_telemetry
  tags             = local.spoke_tags

  depends_on = [
    azurerm_network_security_group.spoke,
    module.spoke_route_table
  ]
}


# Network Security Group with role-specific rules
resource "azurerm_network_security_group" "spoke" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider            = azurerm.spoke
  name                = local.spoke_names.network_security_group
  location            = module.spoke_resource_group.resource.location
  resource_group_name = module.spoke_resource_group.resource.name

  tags = local.spoke_tags
}

# Security Rules - Dynamic based on workload role and configuration
resource "azurerm_network_security_rule" "spoke_rules" {
  for_each = var.spoke_config.virtual_network != null ? var.spoke_config.security_rules : {}

  provider                    = azurerm.spoke
  name                        = each.value.name
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_ranges == null ? each.value.destination_port_range : null
  destination_port_ranges     = each.value.destination_port_ranges != null ? each.value.destination_port_ranges : null
  source_address_prefix       = each.value.source_address_prefixes == null ? each.value.source_address_prefix : null
  source_address_prefixes     = each.value.source_address_prefixes != null ? each.value.source_address_prefixes : null
  destination_address_prefix  = each.value.destination_address_prefix
  resource_group_name         = module.spoke_resource_group.resource.name
  network_security_group_name = azurerm_network_security_group.spoke[0].name
}

# Default Inbound Security Rules
resource "azurerm_network_security_rule" "allow_bastion_host_communication_inbound" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider                    = azurerm.spoke
  name                        = "AllowBastionHostCommunication"
  priority                    = 160
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_ranges     = ["8080", "5701"]
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = module.spoke_resource_group.resource.name
  network_security_group_name = azurerm_network_security_group.spoke[0].name
}

resource "azurerm_network_security_rule" "allow_vnet_inbound" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider                    = azurerm.spoke
  name                        = "AllowVnetInBound"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = module.spoke_resource_group.resource.name
  network_security_group_name = azurerm_network_security_group.spoke[0].name
}

resource "azurerm_network_security_rule" "allow_azure_load_balancer_inbound" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider                    = azurerm.spoke
  name                        = "AllowAzureLoadBalancerInBound"
  priority                    = 4001
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = module.spoke_resource_group.resource.name
  network_security_group_name = azurerm_network_security_group.spoke[0].name
}

resource "azurerm_network_security_rule" "deny_all_inbound" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider                    = azurerm.spoke
  name                        = "DenyAllInBound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = module.spoke_resource_group.resource.name
  network_security_group_name = azurerm_network_security_group.spoke[0].name
}

# Default Outbound Security Rules
resource "azurerm_network_security_rule" "allow_azure_cloud_outbound" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider                    = azurerm.spoke
  name                        = "AzureCloud"
  priority                    = 110
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8443"
  source_address_prefix       = "*"
  destination_address_prefix  = "AzureCloud"
  resource_group_name         = module.spoke_resource_group.resource.name
  network_security_group_name = azurerm_network_security_group.spoke[0].name
}

resource "azurerm_network_security_rule" "allow_azure_monitor_outbound" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider                    = azurerm.spoke
  name                        = "AzureMonitor"
  priority                    = 120
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "AzureMonitor"
  resource_group_name         = module.spoke_resource_group.resource.name
  network_security_group_name = azurerm_network_security_group.spoke[0].name
}

resource "azurerm_network_security_rule" "allow_azure_marketplace_outbound" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider                    = azurerm.spoke
  name                        = "AzureMarketplace"
  priority                    = 130
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "AzureFrontDoor.FrontEnd"
  resource_group_name         = module.spoke_resource_group.resource.name
  network_security_group_name = azurerm_network_security_group.spoke[0].name
}

resource "azurerm_network_security_rule" "allow_windows_activation_outbound" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider                    = azurerm.spoke
  name                        = "WindowsActivation"
  priority                    = 140
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1688"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = module.spoke_resource_group.resource.name
  network_security_group_name = azurerm_network_security_group.spoke[0].name
}

resource "azurerm_network_security_rule" "allow_azure_instance_metadata_outbound" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider                    = azurerm.spoke
  name                        = "AzureInstanceMetadata"
  priority                    = 150
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "169.254.169.254"
  resource_group_name         = module.spoke_resource_group.resource.name
  network_security_group_name = azurerm_network_security_group.spoke[0].name
}

resource "azurerm_network_security_rule" "allow_bastion_communication_outbound" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider                    = azurerm.spoke
  name                        = "AllowBastionCommunication"
  priority                    = 170
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_ranges     = ["8080", "5701"]
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = module.spoke_resource_group.resource.name
  network_security_group_name = azurerm_network_security_group.spoke[0].name
}

resource "azurerm_network_security_rule" "allow_vnet_outbound" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider                    = azurerm.spoke
  name                        = "AllowVnetOutBound"
  priority                    = 4000
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = module.spoke_resource_group.resource.name
  network_security_group_name = azurerm_network_security_group.spoke[0].name
}

resource "azurerm_network_security_rule" "allow_internet_outbound" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider                    = azurerm.spoke
  name                        = "AllowInternetOutBound"
  priority                    = 4001
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = module.spoke_resource_group.resource.name
  network_security_group_name = azurerm_network_security_group.spoke[0].name
}

resource "azurerm_network_security_rule" "deny_all_outbound" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider                    = azurerm.spoke
  name                        = "DenyAllOutBound"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = module.spoke_resource_group.resource.name
  network_security_group_name = azurerm_network_security_group.spoke[0].name
}

# VNet Peering to Hub (if enabled)
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  count = var.spoke_config.virtual_network != null && var.spoke_config.connect_to_hub ? 1 : 0

  provider                     = azurerm.spoke
  name                         = "peer-${local.service}-to-hub"
  resource_group_name          = module.spoke_resource_group.resource.name
  virtual_network_name         = module.spoke_virtual_network[0].resource.name
  remote_virtual_network_id    = var.hub_virtual_network_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# Hub to Spoke peering (reverse direction)
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  count = var.spoke_config.virtual_network != null && var.spoke_config.connect_to_hub ? 1 : 0

  provider = azurerm.connectivity

  name                         = "peer-hub-to-${local.service}"
  resource_group_name          = var.hub_resource_group_name
  virtual_network_name         = var.hub_virtual_network_name
  remote_virtual_network_id    = module.spoke_virtual_network[0].resource.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

# Route Table using AVM module - without routes to prevent recreation
module "spoke_route_table" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  source  = "Azure/avm-res-network-routetable/azurerm"
  version = "~> 0.3.1"

  providers = {
    azurerm = azurerm.spoke
  }

  name                = local.spoke_names.route_table
  location            = module.spoke_resource_group.resource.location
  resource_group_name = module.spoke_resource_group.resource.name

  # Empty routes - will be managed separately to prevent cascade recreation
  routes = {}

  enable_telemetry = var.enable_telemetry
  tags             = local.spoke_tags
}

# Separate route resource with lifecycle rules to prevent firewall IP changes from forcing recreation
resource "azurerm_route" "default_route" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider            = azurerm.spoke
  name                = "DefaultRoute"
  resource_group_name = module.spoke_resource_group.resource.name
  route_table_name    = module.spoke_route_table[0].resource.name
  address_prefix      = "0.0.0.0/0"
  next_hop_type       = var.firewall_private_ip != null ? "VirtualAppliance" : "Internet"
  next_hop_in_ip_address = var.firewall_private_ip

  # Prevent recreation when firewall IP changes to avoid cascade
  lifecycle {
    ignore_changes = [next_hop_in_ip_address]
  }

  depends_on = [module.spoke_route_table]
}


# Storage Account using AVM module
module "spoke_storage" {
  count = var.spoke_config.enable_storage ? 1 : 0

  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "~> 0.6.4"

  providers = {
    azurerm = azurerm.spoke
  }

  name                = local.storage_account_names.general
  resource_group_name = module.spoke_storage_resource_group[0].resource.name
  location            = module.spoke_resource_group.resource.location

  account_tier             = var.spoke_config.storage_config.account_tier
  account_replication_type = var.spoke_config.storage_config.account_replication_type
  account_kind             = var.spoke_config.storage_config.account_kind

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true

  # Network Access Rules Configuration
  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices", "Metrics", "Logging"]
    ip_rules       = var.allow_list_ip
    virtual_network_subnet_ids = var.spoke_config.virtual_network != null ? [
      for subnet in values(module.spoke_virtual_network[0].subnets) : subnet.resource_id
    ] : []
  }

  enable_telemetry = var.enable_telemetry
  tags             = local.spoke_tags
}

# Recovery Services Vault - Primary region for Backup, DR region for ASR targets
module "spoke_recovery_services_vault" {
  count = var.spoke_config.enable_backup ? 1 : 0

  source  = "Azure/avm-res-recoveryservices-vault/azurerm"
  version = "~> 0.3.1"

  providers = {
    azurerm = azurerm.spoke
  }

  name                = local.spoke_names.recovery_vault
  location            = module.spoke_resource_group.resource.location
  resource_group_name = var.environment == "dr" ? module.spoke_recovery_resource_group[0].resource.name : module.spoke_backup_resource_group[0].resource.name

  # Basic vault configuration
  sku                           = var.spoke_config.backup_config != null ? var.spoke_config.backup_config.sku : "Standard"
  storage_mode_type             = var.spoke_config.backup_config != null ? var.spoke_config.backup_config.storage_mode_type : "LocallyRedundant"
  cross_region_restore_enabled  = var.spoke_config.backup_config != null ? var.spoke_config.backup_config.cross_region_restore_enabled : false
  public_network_access_enabled = var.spoke_config.backup_config != null ? var.spoke_config.backup_config.public_network_access_enabled : true
  immutability                  = var.spoke_config.backup_config != null ? var.spoke_config.backup_config.immutability : "Unlocked"

  # VM Backup Policies - multiple policies for different server types
  # See docs/backup-policies.md for detailed policy descriptions and Azure Policy requirements
  # Note: VMs must be assigned to these policies via Azure Policy - policies alone don't protect resources
  vm_backup_policy = var.spoke_config.backup_config != null ? {
    # Basic VM policy for non-critical workloads with shorter retention
    vm_basic_14day = {
      name                           = "VM-Basic-14Day-Daily-Policy"
      timezone                       = "GMT Standard Time"
      policy_type                    = "V2"
      frequency                      = "Daily"
      instant_restore_retention_days = 5
      instant_restore_resource_group = {
        default = {
          prefix = "rg-backup-${var.environment}-${local.location_abbr}-servers"
        }
      }

      backup = {
        time = "01:00"
      }

      retention_daily = 14
    }

    # Standard VM policy with 30-day retention
    vm_standard_30day = {
      name                           = "VM-Standard-30Day-Daily-Policy"
      timezone                       = "GMT Standard Time"
      policy_type                    = "V2"
      frequency                      = "Daily"
      instant_restore_retention_days = 7
      instant_restore_resource_group = {
        default = {
          prefix = "rg-backup-${var.environment}-${local.location_abbr}-servers"
        }
      }

      backup = {
        time = "23:00"
      }

      retention_daily = 30
    }

    # Enhanced VM policy with weekly retention
    vm_enhanced_90day = {
      name                           = "VM-Enhanced-90Day-Weekly-Policy"
      timezone                       = "GMT Standard Time"
      policy_type                    = "V2"
      frequency                      = "Daily"
      instant_restore_retention_days = 7
      instant_restore_resource_group = {
        default = {
          prefix = "rg-backup-${var.environment}-${local.location_abbr}-servers"
        }
      }

      backup = {
        time = "22:30"
      }

      retention_daily = 90

      retention_weekly = {
        count    = 12
        weekdays = ["Saturday"]
      }
    }

    # Extended VM policy with comprehensive long-term retention cycles
    vm_extended_7year = {
      name                           = "VM-Extended-7Year-Lifecycle-Policy"
      timezone                       = "GMT Standard Time"
      policy_type                    = "V2"
      frequency                      = "Daily"
      instant_restore_retention_days = 7
      instant_restore_resource_group = {
        default = {
          prefix = "rg-backup-${var.environment}-${local.location_abbr}-servers"
        }
      }

      backup = {
        time = "22:00"
      }

      retention_daily = 30

      retention_weekly = {
        count    = 12
        weekdays = ["Saturday"]
      }

      retention_monthly = {
        count             = 12
        days              = [1] # First day of each month
        include_last_days = false
      }

      retention_yearly = {
        count             = 7
        months            = ["December"]
        days              = [1] # December 1st
        include_last_days = false
      }
    }
  } : null

  # File Share Backup Policies - for Azure Files protection
  # See docs/backup-policies.md for Azure Policy requirements to automatically protect file shares
  file_share_backup_policy = var.spoke_config.backup_config != null ? {
    # Files Standard Policy: Daily 21:00, 30-day retention for most file shares
    files_standard_30day = {
      name      = "Files-Standard-30Day-Daily-Policy"
      timezone  = "GMT Standard Time"
      frequency = "Daily"

      backup = {
        time = "21:00"
      }

      retention_daily = 30
    }

    # Files Enhanced Policy: Daily 20:00, 90-day retention for important file shares
    files_enhanced_90day = {
      name      = "Files-Enhanced-90Day-Daily-Policy"
      timezone  = "GMT Standard Time"
      frequency = "Daily"

      backup = {
        time = "20:00"
      }

      retention_daily = 90
    }
  } : null

  # Diagnostic settings - simplified configuration
  diagnostic_settings = {
    vault_diagnostics = {
      name                  = "${local.spoke_names.recovery_vault}-diagnostics"
      workspace_resource_id = var.log_analytics_workspace_id
    }
  }

  enable_telemetry = var.enable_telemetry
  tags = merge(local.spoke_tags, {
    Purpose     = var.environment == "dr" ? "Azure Site Recovery" : "Azure Backup"
    Environment = var.environment
  })
}

# Key Vault using AVM module
module "spoke_key_vault" {
  count = var.spoke_config.enable_key_vault ? 1 : 0

  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.10.0"

  providers = {
    azurerm = azurerm.spoke
  }

  name                = local.key_vault_names.main
  location            = module.spoke_resource_group.resource.location
  resource_group_name = module.spoke_servers_resource_group.resource.name
  tenant_id           = data.azurerm_client_config.spoke.tenant_id

  sku_name                        = var.spoke_config.key_vault_config.sku_name
  enabled_for_disk_encryption     = var.spoke_config.key_vault_config.enabled_for_disk_encryption
  enabled_for_deployment          = var.spoke_config.key_vault_config.enabled_for_deployment
  enabled_for_template_deployment = var.spoke_config.key_vault_config.enabled_for_template_deployment
  purge_protection_enabled        = true # Required by Azure Policy

  # Network access controls
  public_network_access_enabled = var.spoke_config.key_vault_config.public_network_access_enabled
  network_acls                  = var.spoke_config.key_vault_config.network_acls

  # Private endpoints if enabled
  private_endpoints = var.spoke_config.key_vault_config.enable_private_endpoint ? {
    "vault" = {
      name                            = "${local.spoke_names.key_vault}-pe"
      subnet_resource_id              = var.spoke_config.key_vault_config.private_endpoint_subnet_id
      subresource_name                = "vault"
      private_service_connection_name = "${local.spoke_names.key_vault}-psc"
      network_interface_name          = "${local.spoke_names.key_vault}-nic"
      private_dns_zone_group_name     = "vault-private-dns-zone-group"
    }
  } : {}

  enable_telemetry = var.enable_telemetry
  tags             = local.spoke_tags
}

# Availability Set for VMs (when needed)
# Availability zones provide better resilience than availability sets
# We'll distribute VMs across zones 1, 2, and 3 instead of using availability sets

# Virtual Machines using AVM module with flexible NIC and disk support
locals {
  # Generate VM instances with availability zone distribution
  vm_instances = var.spoke_config.deploy_virtual_machines ? flatten([
    for vm_key, vm_config in var.spoke_config.virtual_machines : [
      for vm_index in range(vm_config.count) : {
        key      = "${vm_key}-${format("%02d", vm_index)}"
        vm_key   = vm_key
        vm_index = vm_index
        config   = vm_config
        vm_name  = vm_config.vm_name_prefix != null ? "${vm_config.vm_name_prefix}${format("%02d", vm_index + 1)}" : "${upper(vm_key)}-${format("%02d", vm_index + 1)}"
        # Distribute across availability zones
        zone = length(vm_config.availability_zones) > 0 ? vm_config.availability_zones[vm_index % length(vm_config.availability_zones)] : tostring((vm_index % 3) + 1)
      }
    ]
  ]) : []
}

module "spoke_virtual_machines" {
  for_each = {
    for vm in local.vm_instances : vm.key => vm
  }

  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "~> 0.19.0"

  providers = {
    azurerm = azurerm.spoke
  }

  # Basic VM Configuration
  name                = each.value.vm_name
  computer_name       = each.value.vm_name
  location            = module.spoke_resource_group.resource.location
  resource_group_name = module.spoke_servers_resource_group.resource.name
  zone                = each.value.zone

  # OS Configuration
  os_type        = each.value.config.os_type
  sku_size       = each.value.config.vm_size
  admin_username = each.value.config.admin_username

  # Source image configuration using os_sku
  source_image_reference = {
    publisher = each.value.config.os_type == "Windows" ? "MicrosoftWindowsServer" : "Canonical"
    offer     = each.value.config.os_type == "Windows" ? "WindowsServer" : "0001-com-ubuntu-server-jammy"
    sku       = each.value.config.os_sku
    version   = "latest"
  }

  # Multiple Network Interfaces Support with zero-padded naming
  network_interfaces = {
    for nic_idx, nic_config in each.value.config.network_interfaces : "nic${format("%02d", nic_idx + 1)}" => {
      name = "${each.value.vm_name}-nic${format("%02d", nic_idx + 1)}"
      ip_configurations = {
        internal = {
          name                          = "internal"
          private_ip_address_allocation = nic_config.private_ip_allocation_method
          private_ip_subnet_resource_id = module.spoke_virtual_network[0].subnets[nic_config.subnet_name].resource_id
          private_ip_address            = try(nic_config.static_ip_address, each.value.config.static_ip_start != null ? join(".", [split(".", each.value.config.static_ip_start)[0], split(".", each.value.config.static_ip_start)[1], split(".", each.value.config.static_ip_start)[2], tostring(tonumber(split(".", each.value.config.static_ip_start)[3]) + each.value.vm_index)]) : null)
        }
      }
      network_security_group_id     = azurerm_network_security_group.spoke[0].id
      enable_ip_forwarding          = try(nic_config.enable_ip_forwarding, false)
      enable_accelerated_networking = try(nic_config.enable_accelerated_networking, false)
    }
  }

  # OS Disk Configuration with simple naming
  os_disk = {
    name                 = "${each.value.vm_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = each.value.config.os_disk_size_gb
  }

  # Multiple Data Disks Support with zero-padded naming
  data_disk_managed_disks = {
    for disk_idx, disk_config in each.value.config.data_disks : "datadisk${format("%02d", disk_idx + 1)}" => {
      name                      = "${each.value.vm_name}-datadisk${format("%02d", disk_idx + 1)}"
      storage_account_type      = try(disk_config.storage_account_type, "Premium_LRS")
      disk_size_gb              = disk_config.size_gb
      lun                       = disk_config.lun
      caching                   = try(disk_config.caching, "ReadWrite")
      create_option             = try(disk_config.create_option, "Empty")
      disk_encryption_set_id    = try(disk_config.disk_encryption_set_id, null)
      write_accelerator_enabled = try(disk_config.write_accelerator_enabled, false)
    }
  }

  # Identity and Security
  managed_identities = {
    system_assigned = true
  }

  encryption_at_host_enabled = true
  secure_boot_enabled        = true # Enabled with Gen2 TrustedLaunch supported images
  vtpm_enabled               = true # Enabled with Gen2 TrustedLaunch supported images

  # Backup Configuration disabled - Azure Policy will handle
  azure_backup_configurations = {}

  # Monitoring
  boot_diagnostics = true

  # Patch management - matches Azure Policy default
  patch_assessment_mode = "AutomaticByPlatform"

  # Extensions
  extensions = each.value.config.enable_extensions ? {
    azure_monitor_agent = {
      name                       = "AzureMonitorWindowsAgent"
      publisher                  = "Microsoft.Azure.Monitor"
      type                       = each.value.config.os_type == "Windows" ? "AzureMonitorWindowsAgent" : "AzureMonitorLinuxAgent"
      type_handler_version       = "1.0"
      auto_upgrade_minor_version = true
    }
  } : {}

  enable_telemetry = var.enable_telemetry

  tags = merge(local.spoke_tags, {
    # Simplified backup tagging for ALZ policy compatibility
    BackupEnabled    = var.spoke_config.enable_backup ? "True" : "False"
    CriticalWorkload = var.workload_role == "identity" ? "DomainController" : title(each.value.vm_key)
  })

  depends_on = [
    module.spoke_virtual_network,
    azurerm_network_security_group.spoke,
    module.spoke_recovery_services_vault
  ]
}

# Diagnostic Settings for NSG
resource "azurerm_monitor_diagnostic_setting" "spoke_nsg_diagnostics" {
  count = var.spoke_config.virtual_network != null ? 1 : 0

  provider                   = azurerm.spoke
  name                       = "${azurerm_network_security_group.spoke[0].name}-diagnostics"
  target_resource_id         = azurerm_network_security_group.spoke[0].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = [
      "NetworkSecurityGroupEvent",
      "NetworkSecurityGroupRuleCounter"
    ]
    content {
      category = enabled_log.value
    }
  }
}

# Diagnostic Settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "spoke_storage_diagnostics" {
  count = var.spoke_config.enable_storage ? 1 : 0

  provider                   = azurerm.spoke
  name                       = "${module.spoke_storage[0].resource.name}-diagnostics"
  target_resource_id         = module.spoke_storage[0].resource.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = [
      "StorageRead",
      "StorageWrite",
      "StorageDelete"
    ]
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
