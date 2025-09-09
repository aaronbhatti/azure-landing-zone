# Azure Landing Zone - Main Orchestration Module

# Process VM deployments to resolve module references to subnet IDs
locals {
  # VM deployments are now handled through spoke modules with embedded VMs

  # Combine automatic current IP with user-defined allow list
  combined_allow_list_ip = concat(
    [trimspace(data.http.ip.response_body)],           # Current IP automatically detected (single IP without CIDR)
    var.allow_list_ip != null ? var.allow_list_ip : [] # User-defined static IPs
  )

  # Detect if domain controllers are being deployed by checking virtual_machines config
  # Look for any VM with "dc" in the key name or subnet containing "domain-controller"
  identity_has_domain_controllers = var.identity_config.deploy_virtual_machines && var.identity_config.virtual_machines != null ? (
    length([
      for vm_key, vm_config in var.identity_config.virtual_machines : vm_key
      if lower(vm_key) == "dc" || lower(vm_key) == "domain-controller" || contains(split("-", lower(vm_config.subnet_name)), "domain") || contains(split("-", lower(vm_config.subnet_name)), "controllers")
    ]) > 0
  ) : false

  # DNS server configuration for virtual networks
  # Priority: 1) Firewall IP (if enabled and use_firewall_dns = true)
  #           2) Custom DNS servers (if provided)
  #           3) Fallback DNS servers (default: Azure DNS)
  resolved_dns_servers = (
    var.connectivity_config.firewall != null &&
    var.dns_config.use_firewall_dns
    ) ? (
    # Use firewall private IP as DNS server (will be resolved after firewall deployment)
    ["firewall"] # This will be replaced with actual IP in spoke modules
    ) : (
    length(var.dns_config.custom_dns_servers) > 0 ?
    var.dns_config.custom_dns_servers :
    var.dns_config.fallback_dns_servers
  )
}

resource "modtm_telemetry" "telemetry" {
  count = var.enable_telemetry ? 1 : 0

  tags = merge(var.default_tags, {
    Environment = var.environment
    Workload    = "Telemetry"
  })
}

# Management Resources
module "management" {
  count  = var.management_config.enabled ? 1 : 0
  source = "./modules/management"

  providers = {
    azurerm.management   = azurerm.management
    azurerm.connectivity = azurerm.connectivity
  }

  management_config         = var.management_config
  location                  = var.location
  environment               = var.environment
  default_tags              = merge(var.default_tags, { Environment = var.environment })
  enable_telemetry          = var.enable_telemetry
  enable_automation_account = var.enable_automation_account
}

# Core Governance
module "core" {
  count  = var.core_config.enabled ? 1 : 0
  source = "./modules/core"

  providers = {
    azurerm.management   = azurerm.management
    azurerm.connectivity = azurerm.connectivity
  }

  # Merge user core_config with comprehensive dynamic policy defaults for AMA integration
  core_config = var.management_config.enabled ? merge(var.core_config, {
    policy_default_values = merge(
      var.core_config.policy_default_values,
      {
        # Log Analytics Workspace for all monitoring policies
        log_analytics_workspace_id = jsonencode({ 
          value = "/subscriptions/${var.management_subscription_id}/resourceGroups/${module.management[0].resource_group_name}/providers/Microsoft.OperationalInsights/workspaces/${module.management[0].log_analytics_workspace_name}"
        })
        
        # Azure Monitor Agent (AMA) Data Collection Rules
        ama_change_tracking_data_collection_rule_id = jsonencode({ 
          value = "/subscriptions/${var.management_subscription_id}/resourceGroups/${module.management[0].resource_group_name}/providers/Microsoft.Insights/dataCollectionRules/dcr-change-tracking" 
        })
        
        ama_vm_insights_data_collection_rule_id = jsonencode({ 
          value = "/subscriptions/${var.management_subscription_id}/resourceGroups/${module.management[0].resource_group_name}/providers/Microsoft.Insights/dataCollectionRules/dcr-vm-insights" 
        })
        
        ama_mdfc_sql_data_collection_rule_id = jsonencode({ 
          value = "/subscriptions/${var.management_subscription_id}/resourceGroups/${module.management[0].resource_group_name}/providers/Microsoft.Insights/dataCollectionRules/dcr-defender-sql" 
        })
        
        # User-Assigned Managed Identity for AMA
        ama_user_assigned_managed_identity_id = jsonencode({ 
          value = "/subscriptions/${var.management_subscription_id}/resourceGroups/${module.management[0].resource_group_name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-ama" 
        })
        
        ama_user_assigned_managed_identity_name = jsonencode({ 
          value = "uami-ama" 
        })
      },
      # Note: Security contact email is not supported in this ALZ version
      # Future versions may support email_security_contact or similar parameters
      # Conditionally add automation account ID  
      var.enable_automation_account && var.management_config.enabled ? {
        automation_account_id = jsonencode({ 
          value = module.management[0].automation_account_id 
        })
      } : {}
    )
  }) : var.core_config
  
  management_subscription_id   = var.management_subscription_id
  connectivity_subscription_id = var.connectivity_subscription_id
  identity_subscription_id     = var.identity_subscription_id
  location                     = var.location
  environment                  = var.environment
  default_tags                 = var.default_tags
  enable_telemetry             = var.enable_telemetry

  # Dependencies - simplified to avoid type consistency issues
  # The AVM ALZ module will handle dependency resolution internally
  dependencies = {
    policy_assignments = []
  }
}
# Connectivity Resources
module "connectivity" {
  count  = var.connectivity_config.enabled ? 1 : 0
  source = "./modules/connectivity"

  providers = {
    azurerm.connectivity = azurerm.connectivity
  }

  environment         = var.environment
  location            = var.location
  subscription_id     = var.connectivity_subscription_id
  connectivity_config = var.connectivity_config
  default_tags        = var.default_tags
  enable_telemetry    = var.enable_telemetry

  # Pass management outputs for integration
  log_analytics_workspace_id = var.management_config.enabled ? module.management[0].log_analytics_workspace_id : null

  # IP Range Configuration for Firewall Rules
  hub_address_space                  = var.hub_address_space
  identity_spoke_address_space       = var.identity_spoke_address_space
  infrastructure_spoke_address_space = var.infrastructure_spoke_address_space
  avd_spoke_address_space            = var.avd_spoke_address_space
  all_spoke_address_spaces           = var.all_spoke_address_spaces
  domain_controller_ips              = var.domain_controller_ips
  specific_subnet_ranges             = var.specific_subnet_ranges
  external_service_ips               = var.external_service_ips
}

# Identity Resources
module "identity" {
  count  = var.identity_config.enabled ? 1 : 0
  source = "./modules/spoke"

  providers = {
    azurerm.spoke        = azurerm.identity
    azurerm.connectivity = azurerm.connectivity
  }

  environment     = var.environment
  location        = var.location
  subscription_id = var.identity_subscription_id
  workload_role   = "identity"

  # Network Access Configuration
  allow_list_ip = local.combined_allow_list_ip

  # DNS Configuration
  dns_servers         = local.resolved_dns_servers
  firewall_private_ip = var.connectivity_config.enabled && var.connectivity_config.firewall != null ? module.connectivity[0].firewall_private_ip : null

  # Identity spoke configuration
  spoke_config = {
    resource_group_name = var.identity_config.resource_group_name

    # Virtual Network configuration
    virtual_network = {
      name          = var.identity_config.virtual_network.name
      address_space = var.identity_config.virtual_network.address_space
      subnets       = var.identity_config.virtual_network.subnets
    }

    # Connect to hub
    connect_to_hub = var.identity_config.connect_to_hub

    # Identity-specific security rules for domain controllers
    security_rules = local.identity_has_domain_controllers ? {
      "AllowADInbound" = {
        name                    = "AllowADInbound"
        priority                = 1000
        direction               = "Inbound"
        access                  = "Allow"
        protocol                = "*"
        source_port_range       = "*"
        destination_port_ranges = ["53", "88", "135", "389", "445", "464", "636", "3268", "3269"]
        source_address_prefix   = "VirtualNetwork"
      }
    } : {}

    # Storage account (disabled for identity - not typically needed)
    enable_storage = false

    # Backup configuration
    enable_backup = var.identity_config.enable_backup
    backup_config = var.identity_config.enable_backup ? {
      sku                          = "Standard"
      storage_mode_type            = "GeoRedundant"
      cross_region_restore_enabled = true
      soft_delete_enabled          = true
      backup_policy = {
        name            = "DomainControllerBackupPolicy"
        policy_type     = "V2"
        timezone        = "UTC"
        frequency       = "Daily"
        backup_time     = "22:00"
        retention_daily = 30
        retention_weekly = {
          count    = 12
          weekdays = ["Sunday"]
        }
        retention_monthly = {
          count    = 12
          weekdays = ["Sunday"]
          weeks    = ["First"]
        }
        retention_yearly = {
          count    = 5
          weekdays = ["Sunday"]
          weeks    = ["First"]
          months   = ["January"]
        }
      }
    } : null

    # Key Vault for domain credentials
    enable_key_vault = var.identity_config.enable_key_vault
    key_vault_config = var.identity_config.key_vault_config

    # Virtual machines configuration
    deploy_virtual_machines = var.identity_config.deploy_virtual_machines
    virtual_machines        = var.identity_config.virtual_machines
  }

  # Hub connectivity
  hub_virtual_network_id   = var.connectivity_config.enabled ? module.connectivity[0].hub_virtual_network_id : null
  hub_virtual_network_name = var.connectivity_config.enabled ? module.connectivity[0].hub_virtual_network_name : null
  hub_resource_group_name  = var.connectivity_config.enabled ? module.connectivity[0].hub_resource_group_name : null

  # Logging
  log_analytics_workspace_id = var.management_config.enabled ? module.management[0].log_analytics_workspace_id : null

  # Tags
  default_tags = merge(var.default_tags, { Environment = var.environment })

  # Telemetry
  enable_telemetry = var.enable_telemetry
}


# Infrastructure Resources
module "infrastructure" {
  count  = var.infra_config.enabled ? 1 : 0
  source = "./modules/spoke"

  providers = {
    azurerm.spoke        = azurerm.infra
    azurerm.connectivity = azurerm.connectivity
  }

  environment     = var.environment
  location        = var.location
  subscription_id = var.infra_subscription_id != null ? var.infra_subscription_id : var.management_subscription_id
  workload_role   = "infra"

  # Network Access Configuration
  allow_list_ip = local.combined_allow_list_ip

  # DNS Configuration
  dns_servers         = local.resolved_dns_servers
  firewall_private_ip = var.connectivity_config.enabled && var.connectivity_config.firewall != null ? module.connectivity[0].firewall_private_ip : null

  # Infrastructure spoke configuration
  spoke_config = {
    resource_group_name = var.infra_config.resource_group_name

    # Virtual Network configuration
    virtual_network = {
      name          = var.infra_config.virtual_network.name
      address_space = var.infra_config.virtual_network.address_space
      subnets       = var.infra_config.virtual_network.subnets
    }

    # Connect to hub
    connect_to_hub = var.infra_config.connect_to_hub

    # Infrastructure-specific security rules (minimal - allows VNet traffic)
    security_rules = {}

    # Storage account
    enable_storage = var.infra_config.enable_storage

    # Backup configuration
    enable_backup = var.infra_config.enable_backup
    backup_config = var.infra_config.backup_config

    # Key Vault (not enabled by default for infra)
    enable_key_vault = false

    # Virtual machines configuration
    deploy_virtual_machines = var.infra_config.deploy_virtual_machines
    virtual_machines        = var.infra_config.virtual_machines
  }

  # Hub connectivity
  hub_virtual_network_id   = var.connectivity_config.enabled ? module.connectivity[0].hub_virtual_network_id : null
  hub_virtual_network_name = var.connectivity_config.enabled ? module.connectivity[0].hub_virtual_network_name : null
  hub_resource_group_name  = var.connectivity_config.enabled ? module.connectivity[0].hub_resource_group_name : null

  # Logging
  log_analytics_workspace_id = var.management_config.enabled ? module.management[0].log_analytics_workspace_id : null

  # Tags
  default_tags = merge(var.default_tags, { Environment = var.environment })

  # Telemetry
  enable_telemetry = var.enable_telemetry
}

# Azure Virtual Desktop (AVD) Configuration
module "avd" {
  count  = var.avd_config.enabled ? 1 : 0
  source = "./modules/avd"

  providers = {
    azurerm.avd          = azurerm.avd
    azurerm.connectivity = azurerm.connectivity
  }

  environment      = var.environment
  location         = var.location
  subscription_id  = var.avd_subscription_id
  avd_config       = var.avd_config
  allow_list_ip    = local.combined_allow_list_ip
  default_tags     = merge(var.default_tags, { Environment = var.environment })
  enable_telemetry = var.enable_telemetry

  # DNS Configuration
  dns_servers         = local.resolved_dns_servers
  firewall_private_ip = var.connectivity_config.enabled && var.connectivity_config.firewall != null ? module.connectivity[0].firewall_private_ip : null

  # Pass dependencies from other modules
  log_analytics_workspace_id = var.management_config.enabled ? module.management[0].log_analytics_workspace_id : null
  hub_virtual_network_id     = var.avd_config.connect_to_hub && var.connectivity_config.enabled ? module.connectivity[0].hub_virtual_network_id : null
  hub_virtual_network_name   = var.avd_config.connect_to_hub && var.connectivity_config.enabled ? module.connectivity[0].hub_virtual_network_name : null
  hub_resource_group_name    = var.avd_config.connect_to_hub && var.connectivity_config.enabled ? module.connectivity[0].hub_resource_group_name : null
}

# Azure Image Builder (AIB) Configuration
module "aib" {
  count  = var.aib_config.enabled ? 1 : 0
  source = "./modules/aib"

  providers = {
    azurerm = azurerm.aib
  }

  org_name         = var.org_name
  environment      = var.environment
  location         = var.location
  subscription_id  = var.aib_subscription_id
  aib_config       = var.aib_config
  default_tags     = merge(var.default_tags, { Environment = var.environment })
  enable_telemetry = var.enable_telemetry
  allow_list_ip    = local.combined_allow_list_ip

  # Pass private endpoint configuration if connectivity is configured
  private_endpoint_subnet_id = var.aib_config.enable_private_endpoints && var.connectivity_config.enabled ? "${module.connectivity[0].hub_virtual_network_id}/subnets/private-endpoints" : null

  private_dns_zone_blob_id = var.aib_config.enable_private_endpoints && var.connectivity_config.enabled && var.connectivity_config.private_dns.enabled ? try(module.connectivity[0].private_dns_zone_ids["privatelink.blob.core.windows.net"], null) : null

  private_dns_zone_file_id = var.aib_config.enable_private_endpoints && var.connectivity_config.enabled && var.connectivity_config.private_dns.enabled ? try(module.connectivity[0].private_dns_zone_ids["privatelink.file.core.windows.net"], null) : null
}

