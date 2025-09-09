# AVD Module - Azure Virtual Desktop infrastructure using AVM pattern modules


resource "modtm_telemetry" "avd" {
  count = var.enable_telemetry ? 1 : 0

  tags = local.avd_tags
}

# AVD Resource Group using AVM module
module "avd_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = ">= 0.1.0, < 1.0.0"

  providers = {
    azurerm = azurerm.avd
  }

  name     = local.avd_names.service_resource_group
  location = var.location

  enable_telemetry = var.enable_telemetry

  tags = merge(var.default_tags, {
    Workload = "Azure Virtual Desktop"
  })
}

# AVD Network Resource Group using AVM module
module "avd_network_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = ">= 0.1.0, < 1.0.0"

  providers = {
    azurerm = azurerm.avd
  }

  name     = local.avd_names.network_resource_group
  location = var.location

  enable_telemetry = var.enable_telemetry

  tags = merge(var.default_tags, {
    Workload = "Azure Virtual Desktop"
    Purpose  = "Network"
  })
}

# AVD Storage Resource Group using AVM module
module "avd_storage_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = ">= 0.1.0, < 1.0.0"

  providers = {
    azurerm = azurerm.avd
  }

  name     = local.avd_names.storage_resource_group
  location = var.location

  enable_telemetry = var.enable_telemetry

  tags = merge(var.default_tags, {
    Workload = "Azure Virtual Desktop"
    Purpose  = "Storage"
  })
}


# AVD Session Hosts Resource Group using AVM module
module "avd_hostpool_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = ">= 0.1.0, < 1.0.0"

  providers = {
    azurerm = azurerm.avd
  }

  name     = local.avd_names.hostpool_resource_group
  location = var.location

  enable_telemetry = var.enable_telemetry

  tags = merge(var.default_tags, {
    Workload = "Azure Virtual Desktop"
    Purpose  = "Hostpool"
  })
}

# AVD Management Plane using AVM pattern module
module "avd_management_plane" {
  source  = "Azure/avm-ptn-avd-lza-managementplane/azurerm"
  version = "~> 0.3.2"

  providers = {
    azurerm = azurerm.avd
  }

  # Resource Group and Location
  resource_group_name = module.avd_resource_group.resource.name

  # Required attributes for host pool and workspace
  virtual_desktop_host_pool_resource_group_name         = module.avd_resource_group.resource.name
  virtual_desktop_host_pool_location                    = module.avd_resource_group.resource.location
  virtual_desktop_workspace_location                    = module.avd_resource_group.resource.location
  virtual_desktop_application_group_location            = module.avd_resource_group.resource.location
  virtual_desktop_application_group_resource_group_name = module.avd_resource_group.resource.name

  # Virtual Desktop Workspace (flattened structure)
  virtual_desktop_workspace_name          = local.avd_names.workspace
  virtual_desktop_workspace_friendly_name = var.avd_config.workspace_friendly_name
  virtual_desktop_workspace_description   = var.avd_config.workspace_description
  public_network_access_enabled           = var.avd_config.public_network_access_enabled

  # Host Pool Configuration (flattened structure)
  virtual_desktop_host_pool_name                             = local.avd_names.host_pool
  virtual_desktop_host_pool_friendly_name                    = var.avd_config.host_pool.friendly_name
  virtual_desktop_host_pool_description                      = var.avd_config.host_pool.description
  virtual_desktop_host_pool_type                             = var.avd_config.host_pool.type
  virtual_desktop_host_pool_load_balancer_type               = var.avd_config.host_pool.load_balancer_type
  virtual_desktop_host_pool_maximum_sessions_allowed         = var.avd_config.host_pool.maximum_sessions_allowed
  virtual_desktop_host_pool_personal_desktop_assignment_type = var.avd_config.host_pool.personal_desktop_assignment_type
  virtual_desktop_host_pool_custom_rdp_properties            = var.avd_config.host_pool.custom_rdp_properties != null ? { value = var.avd_config.host_pool.custom_rdp_properties } : null
  virtual_desktop_host_pool_start_vm_on_connect              = var.avd_config.host_pool.start_vm_on_connect
  virtual_desktop_host_pool_validate_environment             = var.avd_config.host_pool.validate_environment

  # Application Group (flattened structure)
  virtual_desktop_application_group_name                         = local.avd_names.application_group
  virtual_desktop_application_group_friendly_name                = var.avd_config.application_group.friendly_name
  virtual_desktop_application_group_description                  = var.avd_config.application_group.description
  virtual_desktop_application_group_type                         = var.avd_config.application_group.type
  virtual_desktop_application_group_default_desktop_display_name = var.avd_config.application_group.default_desktop_display_name

  # Scaling plan parameters (always created with defaults)
  virtual_desktop_scaling_plan_name                = var.avd_config.scaling_plan.name
  virtual_desktop_scaling_plan_resource_group_name = module.avd_resource_group.resource.name
  virtual_desktop_scaling_plan_location            = module.avd_resource_group.resource.location
  virtual_desktop_scaling_plan_time_zone           = var.avd_config.scaling_plan.time_zone
  virtual_desktop_scaling_plan_schedule = [
    for schedule_name, schedule in var.avd_config.scaling_plan.schedules : {
      days_of_week                         = schedule.days_of_week
      name                                 = schedule_name
      off_peak_load_balancing_algorithm    = schedule.off_peak_load_balancing_algorithm
      off_peak_start_time                  = schedule.off_peak_start_time
      peak_load_balancing_algorithm        = schedule.peak_load_balancing_algorithm
      peak_start_time                      = schedule.peak_start_time
      ramp_down_capacity_threshold_percent = schedule.ramp_down_capacity_threshold_percent
      ramp_down_force_logoff_users         = schedule.ramp_down_force_logoff_users
      ramp_down_load_balancing_algorithm   = schedule.ramp_down_load_balancing_algorithm
      ramp_down_minimum_hosts_percent      = schedule.ramp_down_minimum_hosts_percent
      ramp_down_notification_message       = schedule.ramp_down_notification_message
      ramp_down_start_time                 = schedule.ramp_down_start_time
      ramp_down_stop_hosts_when            = schedule.ramp_down_stop_hosts_when
      ramp_down_wait_time_minutes          = schedule.ramp_down_wait_time_minutes
      ramp_up_capacity_threshold_percent   = schedule.ramp_up_capacity_threshold_percent
      ramp_up_load_balancing_algorithm     = schedule.ramp_up_load_balancing_algorithm
      ramp_up_minimum_hosts_percent        = schedule.ramp_up_minimum_hosts_percent
      ramp_up_start_time                   = schedule.ramp_up_start_time
    }
  ]

  enable_telemetry = var.enable_telemetry

  # Resource-specific tags for AVD components
  virtual_desktop_host_pool_tags         = local.avd_tags
  virtual_desktop_workspace_tags         = local.avd_tags
  virtual_desktop_application_group_tags = local.avd_tags
  virtual_desktop_scaling_plan_tags      = local.avd_tags
}

# AVD Insights using AVM pattern module (Optional) - Connected to Management Log Analytics
module "avd_insights" {
  count = var.avd_config.enable_insights ? 1 : 0

  source  = "Azure/avm-ptn-avd-lza-insights/azurerm"
  version = "~> 0.1.4"

  providers = {
    azurerm = azurerm.avd
  }

  # Required attributes for new API
  monitor_data_collection_rule_resource_group_name = module.avd_resource_group.resource.name
  monitor_data_collection_rule_location            = module.avd_resource_group.resource.location
  monitor_data_collection_rule_name                = "microsoft-avdi-${local.env_prefix}-${local.service}-${local.location_abbr}"

  # Configure data sources
  monitor_data_collection_rule_data_sources = {
    windows_event_log = [
      {
        name    = "eventLogsDataSource"
        streams = ["Microsoft-Event"]
        x_path_queries = [
          "Microsoft-Windows-TerminalServices-Gateway/Operational!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]",
          "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]",
          "System!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]",
          "Microsoft-FSLogix-Apps/Operational!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]"
        ]
      }
    ]
    performance_counter = [
      {
        counter_specifiers = [
          "\\LogicalDisk(C:)\\Avg. Disk Queue Length",
          "\\LogicalDisk(C:)\\Current Disk Queue Length",
          "\\Memory\\Available Mbytes",
          "\\Memory\\Page Faults/sec",
          "\\Memory\\Pages/sec",
          "\\Memory\\% Committed Bytes In Use",
          "\\PhysicalDisk(*)\\Avg. Disk Queue Length",
          "\\PhysicalDisk(*)\\Avg. Disk sec/Read",
          "\\PhysicalDisk(*)\\Avg. Disk sec/Transfer",
          "\\PhysicalDisk(*)\\Avg. Disk sec/Write",
          "\\Processor Information(_Total)\\% Processor Time",
          "\\User Input Delay per Process(*)\\Max Input Delay",
          "\\User Input Delay per Session(*)\\Max Input Delay",
          "\\RemoteFX Network(*)\\Current TCP RTT",
          "\\RemoteFX Network(*)\\Current UDP Bandwidth"
        ]
        name                          = "perfCounterDataSource60"
        sampling_frequency_in_seconds = 60
        streams                       = ["Microsoft-Perf"]
      }
    ]
  }

  # Configure destinations to use management Log Analytics workspace
  monitor_data_collection_rule_destinations = {
    log_analytics = {
      workspace_resource_id = var.log_analytics_workspace_id
      name                  = "management-workspace"
    }
  }

  # Data flow configuration pointing to management workspace
  monitor_data_collection_rule_data_flow = [
    {
      streams      = ["Microsoft-Event"]
      destinations = ["management-workspace"]
    },
    {
      streams      = ["Microsoft-Perf"]
      destinations = ["management-workspace"]
    }
  ]

  enable_telemetry = var.enable_telemetry
}

# Resolve DNS servers - replace "firewall" with actual firewall IP if provided
locals {
  resolved_dns_servers = var.dns_servers != null ? [
    for dns in var.dns_servers : dns == "firewall" && var.firewall_private_ip != null ? var.firewall_private_ip : dns
  ] : ["168.63.129.16"]
}

# AVD Session Hosts Virtual Network (if not connecting to existing)
module "avd_virtual_network" {
  count = var.avd_config.create_virtual_network ? 1 : 0

  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.10.0"

  providers = {
    azurerm = azurerm.avd
  }

  name                = local.avd_names.virtual_network
  location            = module.avd_network_resource_group.resource.location
  resource_group_name = module.avd_network_resource_group.resource.name
  address_space       = var.avd_config.virtual_network.address_space
  dns_servers = local.resolved_dns_servers != null ? {
    dns_servers = toset(local.resolved_dns_servers)
  } : null

  # AVD specific subnets
  subnets = {
    for k, v in var.avd_config.virtual_network.subnets : k => {
      name              = k # Use map key as subnet name
      address_prefixes  = v.address_prefixes
      service_endpoints = v.service_endpoints
      route_table = var.avd_config.create_virtual_network ? {
        id = module.avd_route_table[0].resource_id
      } : null
    }
  }

  enable_telemetry = var.enable_telemetry

  tags = merge(var.default_tags, {
    Workload = "Azure Virtual Desktop"
  })
}

# Route Table for AVD subnets using AVM module
module "avd_route_table" {
  count = var.avd_config.create_virtual_network ? 1 : 0

  source  = "Azure/avm-res-network-routetable/azurerm"
  version = "~> 0.3.1"

  providers = {
    azurerm = azurerm.avd
  }

  name                = "rt-${local.env_prefix}-${local.service}-${local.location_abbr}"
  location            = module.avd_resource_group.resource.location
  resource_group_name = module.avd_network_resource_group.resource.name

  # Route configuration
  routes = {
    "DefaultRoute" = {
      name                   = "defaultroute"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = var.firewall_private_ip != null ? "VirtualAppliance" : "Internet"
      next_hop_in_ip_address = var.firewall_private_ip != null ? var.firewall_private_ip : null
    }
  }

  enable_telemetry = var.enable_telemetry

  tags = merge(var.default_tags, {
    Workload = "Azure Virtual Desktop"
  })
}


# VNet Peering to Hub (if enabled and creating new VNet)
resource "azurerm_virtual_network_peering" "avd_to_hub" {
  count = var.avd_config.create_virtual_network && var.avd_config.connect_to_hub ? 1 : 0

  provider                     = azurerm.avd
  name                         = "peer-avd-to-hub"
  resource_group_name          = module.avd_network_resource_group.resource.name
  virtual_network_name         = module.avd_virtual_network[0].resource.name
  remote_virtual_network_id    = var.hub_virtual_network_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# Hub to AVD peering (reverse direction)
resource "azurerm_virtual_network_peering" "hub_to_avd" {
  count = var.avd_config.create_virtual_network && var.avd_config.connect_to_hub ? 1 : 0

  provider = azurerm.connectivity

  name                         = "peer-hub-to-avd"
  resource_group_name          = var.hub_resource_group_name
  virtual_network_name         = var.hub_virtual_network_name
  remote_virtual_network_id    = module.avd_virtual_network[0].resource.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

# Network Security Group for AVD subnets
module "avd_nsg" {
  count = var.avd_config.create_virtual_network ? 1 : 0

  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "~> 0.5.0"

  providers = {
    azurerm = azurerm.avd
  }

  name                = local.avd_names.session_hosts_nsg
  location            = module.avd_network_resource_group.resource.location
  resource_group_name = module.avd_network_resource_group.resource.name

  # Comprehensive security rules with AVD-specific additions
  security_rules = {
    # AVD-specific rules
    "AllowAVDServiceTraffic" = {
      name                       = "AllowAVDServiceTraffic"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["443"]
      source_address_prefix      = "AzureCloud"
      destination_address_prefix = "*"
    }
    # Default Inbound Rules
    "AllowBastionHostCommunication" = {
      name                       = "AllowBastionHostCommunication"
      priority                   = 160
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_ranges    = ["8080", "5701"]
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    }
    "AllowVnetInBound" = {
      name                       = "AllowVnetInBound"
      priority                   = 4000
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    }
    "AllowAzureLoadBalancerInBound" = {
      name                       = "AllowAzureLoadBalancerInBound"
      priority                   = 4001
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "*"
    }
    "DenyAllInBound" = {
      name                       = "DenyAllInBound"
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
    # Default Outbound Rules
    "AzureCloud" = {
      name                       = "AzureCloud"
      priority                   = 110
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "8443"
      source_address_prefix      = "*"
      destination_address_prefix = "AzureCloud"
    }
    "AzureMonitor" = {
      name                       = "AzureMonitor"
      priority                   = 120
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "*"
      destination_address_prefix = "AzureMonitor"
    }
    "AzureMarketplace" = {
      name                       = "AzureMarketplace"
      priority                   = 130
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "*"
      destination_address_prefix = "AzureFrontDoor.FrontEnd"
    }
    "WindowsActivation" = {
      name                       = "WindowsActivation"
      priority                   = 140
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "1688"
      source_address_prefix      = "*"
      destination_address_prefix = "Internet"
    }
    "AzureInstanceMetadata" = {
      name                       = "AzureInstanceMetadata"
      priority                   = 150
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = "*"
      destination_address_prefix = "169.254.169.254"
    }
    "AllowBastionCommunication" = {
      name                       = "AllowBastionCommunication"
      priority                   = 170
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_ranges    = ["8080", "5701"]
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    }
    "AllowVnetOutBound" = {
      name                       = "AllowVnetOutBound"
      priority                   = 4000
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    }
    "AllowInternetOutBound" = {
      name                       = "AllowInternetOutBound"
      priority                   = 4001
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "Internet"
    }
    "DenyAllOutBound" = {
      name                       = "DenyAllOutBound"
      priority                   = 4096
      direction                  = "Outbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
    "AllowAzureKMS" = {
      name                       = "AllowAzureKMS"
      priority                   = 1002
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "1688"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }

  enable_telemetry = var.enable_telemetry

  tags = merge(var.default_tags, {
    Workload = "Azure Virtual Desktop"
  })
}

# Azure Files Storage Account for FSLogix using AVM
module "fslogix_storage_account" {
  count = var.avd_config.fslogix.enabled ? 1 : 0

  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "~> 0.6.4"

  providers = {
    azurerm = azurerm.avd
  }

  # Storage Account Configuration
  name                = local.storage_account_names.profiles
  location            = module.avd_storage_resource_group.resource.location
  resource_group_name = module.avd_storage_resource_group.resource.name

  # Premium Files Storage Configuration
  account_kind             = "FileStorage"
  account_tier             = "Premium"
  account_replication_type = "LRS" # Premium Files only supports LRS

  # Network Access Configuration
  public_network_access_enabled = true

  # Network Access Rules Configuration
  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices", "Metrics", "Logging"]
    ip_rules       = var.allow_list_ip
    virtual_network_subnet_ids = var.avd_config.create_virtual_network ? [
      for subnet in values(module.avd_virtual_network[0].subnets) : subnet.resource_id
      ] : [
      var.avd_config.existing_subnet_id
    ]
  }


  # Private Endpoint Configuration
  private_endpoints = var.avd_config.fslogix.enable_private_endpoint ? {
    "file" = {
      name                                    = local.avd_names.storage_private_endpoint
      subnet_resource_id                      = var.avd_config.create_virtual_network ? values(module.avd_virtual_network[0].subnets)[0].resource_id : var.avd_config.existing_subnet_id
      subresource_name                        = "file"
      application_security_group_resource_ids = []
      private_dns_zone_group_name             = "file-private-dns-zone-group"
      private_dns_zone_resource_ids           = []

      # Network interface configuration
      network_interface_name = "nic-pe-st-${local.env_prefix}-${local.service}-${local.location_abbr}"

      # Private service connection
      private_service_connection_name = "psc-st-${local.env_prefix}-${local.service}-${local.location_abbr}"
    }
  } : {}


  enable_telemetry = var.enable_telemetry

  tags = merge(var.default_tags, {
    Workload = "Azure Virtual Desktop"
  })
}

# FSLogix Profile File Share
resource "azurerm_storage_share" "fslogix_profiles" {
  count              = var.avd_config.fslogix.enabled ? 1 : 0
  name               = "profiles"
  storage_account_id = module.fslogix_storage_account[0].resource_id
  quota              = var.avd_config.fslogix.profile_share_size_gb
  enabled_protocol   = "SMB"

  metadata = {
    purpose     = "fslogix-profiles"
    environment = var.environment
  }
}

# FSLogix Container File Share
resource "azurerm_storage_share" "fslogix_containers" {
  count = var.avd_config.fslogix.enabled ? 1 : 0

  name               = "containers"
  storage_account_id = module.fslogix_storage_account[0].resource_id
  quota              = var.avd_config.fslogix.container_share_size_gb
  enabled_protocol   = "SMB"

  metadata = {
    purpose     = "fslogix-containers"
    environment = var.environment
  }
}

# Data source to get the Azure Virtual Desktop service principal
data "azuread_service_principal" "avd" {
  count     = var.avd_config.enable_start_vm_rbac ? 1 : 0
  client_id = "9cdead84-a844-4324-93f2-b2e6bb768d07" # Fixed Azure Virtual Desktop service principal client ID
}

# Role assignment for AVD service principal to power on VMs (required for Start VM on Connect)
resource "azurerm_role_assignment" "avd_power_on" {
  count                            = var.avd_config.enable_start_vm_rbac ? 1 : 0
  scope                            = "/subscriptions/${var.subscription_id}"
  role_definition_name             = "Desktop Virtualization Power On Contributor"
  principal_id                     = data.azuread_service_principal.avd[0].object_id
  skip_service_principal_aad_check = true
}
