# Global Configuration
variable "org_name" {
  description = "The name of the organization"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{1,62}[a-zA-Z0-9]$", var.org_name))
    error_message = "Organization name must be between 3-64 characters, alphanumeric, hyphens, and underscores only."
  }
}

variable "environment" {
  description = "The environment name (e.g., dev, test, staging, prod)"
  type        = string
  validation {
    condition     = contains(["Dev", "Test", "Staging", "Prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging or prod"
  }
}

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
}

variable "enable_telemetry" {
  description = "Enable telemetry for the deployment"
  type        = bool
  default     = false
}

variable "enable_automation_account" {
  description = "Enable deployment of Azure Automation Account in management module"
  type        = bool
  default     = true
}


# Backend Configuration (optional)
variable "backend_config" {
  description = "Optional remote backend configuration for state management"
  type = object({
    enabled              = optional(bool, false)
    resource_group_name  = optional(string)
    storage_account_name = optional(string)
    container_name       = optional(string, "tfstate")
    key                  = optional(string, "azure-landing-zone.tfstate")
  })
  default = {
    enabled = false
  }
}

# Subscription Configuration
variable "management_subscription_id" {
  description = "The subscription ID for the management resources"
  type        = string
}

variable "connectivity_subscription_id" {
  description = "The subscription ID for the connectivity resources"
  type        = string
}

variable "identity_subscription_id" {
  description = "The subscription ID for the identity resources (optional)"
  type        = string
  default     = null
}

variable "infra_subscription_id" {
  description = "The subscription ID for the infrastructure resources (optional)"
  type        = string
  default     = null
}

variable "avd_subscription_id" {
  description = "The subscription ID for the Azure Virtual Desktop resources (optional)"
  type        = string
  default     = null
}

variable "aib_subscription_id" {
  description = "The subscription ID for the Azure Image Builder resources (optional)"
  type        = string
  default     = null
}


# Core Configuration (ALZ Governance)
variable "core_config" {
  description = "Configuration for ALZ core governance (management groups, policies, etc.)"
  type = object({
    # Enable/disable core layer
    enabled = optional(bool, true)

    # Management Group Configuration  
    management_group_display_name = optional(string, "Azure Landing Zones")
    management_group_id           = optional(string) # Will be set from org_name
    management_group_parent_id    = optional(string) # If null, uses tenant root management group dynamically

    # Policy Configuration  
    enable_policy_assignments = optional(bool, true)
    policy_default_values     = optional(map(any), {})
    security_contact_email    = optional(string)

    # Enhanced Archetype Configuration with Policy Overrides
    archetypes = optional(map(object({
      policy_assignments     = optional(list(string), [])
      policy_definitions     = optional(list(string), [])
      policy_set_definitions = optional(list(string), [])
      role_definitions       = optional(list(string), [])
      archetype_config = optional(object({
        parameters     = optional(map(any), {})
        access_control = optional(map(list(string)), {})
        }), {
        parameters     = {}
        access_control = {}
      })
    })), {})

    # Custom Policy Assignments Configuration
    custom_policy_assignments = optional(map(object({
      display_name         = string
      description          = optional(string, "")
      policy_definition_id = string
      parameters           = optional(map(any), {})
      scope                = string # Management group ID or subscription ID
      not_scopes           = optional(list(string), [])
      enforcement_mode     = optional(string, "Default") # Default or DoNotEnforce
      location             = optional(string, "")
      identity = optional(object({
        type         = optional(string, "SystemAssigned")
        identity_ids = optional(list(string), [])
      }), null)
    })), {})

    # Custom Policy Definitions Configuration  
    custom_policy_definitions = optional(map(object({
      name         = string
      display_name = string
      description  = optional(string, "")
      policy_type  = optional(string, "Custom")
      mode         = optional(string, "All")
      metadata     = optional(map(any), {})
      parameters   = optional(map(any), {})
      policy_rule  = any # The actual policy rule JSON
    })), {})

    # Policy Initiative (Policy Set) Definitions
    custom_policy_set_definitions = optional(map(object({
      name         = string
      display_name = string
      description  = optional(string, "")
      policy_type  = optional(string, "Custom")
      metadata     = optional(map(any), {})
      parameters   = optional(map(any), {})
      policy_definition_references = list(object({
        policy_definition_id = string
        parameter_values     = optional(map(any), {})
        reference_id         = optional(string)
        policy_group_names   = optional(list(string), [])
      }))
    })), {})

  })
  default = {
    enabled                       = true
    management_group_display_name = "Azure Landing Zones"
    enable_policy_assignments     = true
    policy_default_values         = {}
    security_contact_email        = null
    archetypes                    = {}
    custom_policy_assignments     = {}
    custom_policy_definitions     = {}
    custom_policy_set_definitions = {}

  }
}

# DNS Configuration for Virtual Networks
variable "dns_config" {
  description = "DNS configuration for virtual networks. If firewall is enabled and use_firewall_dns is true, firewall IP will be used as DNS server."
  type = object({
    # Custom DNS servers to use across all virtual networks
    # These will be ignored if use_firewall_dns is true and firewall is enabled
    custom_dns_servers = optional(list(string), [])

    # Whether to automatically use Azure Firewall as DNS server when firewall is enabled
    # When true and firewall is enabled: firewall private IP will be used as DNS server
    # When false: uses custom_dns_servers or Azure default DNS (168.63.129.16)
    use_firewall_dns = optional(bool, true)

    # Fallback DNS servers when firewall DNS is not available
    # Used when firewall is disabled or use_firewall_dns is false
    fallback_dns_servers = optional(list(string), ["168.63.129.16"])
  })
  default = {
    custom_dns_servers   = []
    use_firewall_dns     = true
    fallback_dns_servers = ["168.63.129.16"]
  }
}

# Management Configuration (ALZ Management Resources)
variable "management_config" {
  description = "Configuration for ALZ management resources (Log Analytics, Automation Account, etc.)"
  type = object({
    # Enable/disable management layer
    enabled = optional(bool, true)

    # Resource Group Configuration
    resource_group_name = optional(string)

    # Log Analytics Configuration
    log_analytics = object({
      workspace_name    = optional(string)
      retention_in_days = optional(number, 30)
      sku               = optional(string, "PerGB2018")
    })

    # Automation Account Configuration
    automation_account = object({
      name = optional(string)
      sku  = optional(string, "Basic")
    })
  })
  default = {
    enabled = true
    log_analytics = {
      retention_in_days = 30
      sku               = "PerGB2018"
    }
    automation_account = {
      sku = "Basic"
    }
  }
}

# Sentinel Configuration
variable "sentinel_config" {
  description = "Configuration for Microsoft Sentinel onboarding"
  type = object({
    # Enable/disable Sentinel onboarding
    enabled = optional(bool, false)

    # Sentinel onboarding configuration
    name                          = optional(string, "default")
    customer_managed_key_enabled  = optional(bool, false)
  })
  default = {
    enabled                       = false
    name                          = "default"
    customer_managed_key_enabled  = false
  }
}

# Connectivity Configuration (ALZ Hub and Spoke)
variable "connectivity_config" {
  description = "Configuration for ALZ hub and spoke connectivity resources"
  type = object({
    # Enable/disable connectivity layer
    enabled = optional(bool, true)

    resource_group_name = optional(string)

    # Hub Virtual Network Configuration
    hub_virtual_network = object({
      name          = optional(string)
      address_space = list(string)
      subnets = map(object({
        address_prefixes  = list(string)
        service_endpoints = optional(list(string), [])
        delegations = optional(list(object({
          name = string
          service_delegation = object({
            name    = string
            actions = optional(list(string))
          })
        })), [])
      }))
    })

    # DDoS Protection Configuration
    ddos_protection = optional(object({
      enabled = optional(bool, false)
      }), {
      enabled = false
    })

    # Azure Firewall Configuration
    firewall = optional(object({
      name     = optional(string)
      sku_name = optional(string, "AZFW_VNet")
      sku_tier = optional(string, "Standard")

      # Firewall Policy Configuration
      policy = optional(object({
        # Threat Intelligence Mode
        threat_intelligence_mode = optional(string, "Alert")

        # DNS Settings
        dns_settings = optional(object({
          servers      = optional(list(string), [])
          enable_proxy = optional(bool, true)
          }), {
          servers      = []
          enable_proxy = true
        })

        # Custom Application Rule Collections (merged with defaults from firewall-rules.tf)
        application_rule_collections = optional(list(object({
          name     = string
          priority = number
          action   = string
          rules = list(object({
            name        = string
            description = optional(string, "")
            protocols = list(object({
              type = string
              port = number
            }))
            source_addresses      = optional(list(string), [])
            source_ip_groups      = optional(list(string), [])
            destination_fqdns     = optional(list(string), [])
            destination_urls      = optional(list(string), [])
            destination_addresses = optional(list(string), [])
            destination_ip_groups = optional(list(string), [])
            web_categories        = optional(list(string), [])
            fqdn_tags             = optional(list(string), [])
          }))
        })), [])

        # Custom Network Rule Collections (merged with defaults from firewall-rules.tf)
        network_rule_collections = optional(list(object({
          name     = string
          priority = number
          action   = string
          rules = list(object({
            name                  = string
            description           = optional(string, "")
            protocols             = list(string)
            source_addresses      = optional(list(string), [])
            source_ip_groups      = optional(list(string), [])
            destination_addresses = optional(list(string), [])
            destination_ip_groups = optional(list(string), [])
            destination_fqdns     = optional(list(string), [])
            destination_ports     = list(string)
          }))
        })), [])
        }), {
        threat_intelligence_mode = "Alert"
        dns_settings = {
          servers      = []
          enable_proxy = true
        }
        application_rule_collections = []
        network_rule_collections     = []
      })
    }))

    # VPN Gateway Configuration (if configured, will be deployed)
    vpn_gateway = optional(object({
      enabled  = optional(bool, false)
      name     = optional(string)
      type     = optional(string, "Vpn")
      vpn_type = optional(string, "RouteBased")
      sku      = optional(string, "VpnGw1")
    }))

    # ExpressRoute Gateway Configuration (if configured, will be deployed)
    expressroute_gateway = optional(object({
      enabled = optional(bool, false)
      name    = optional(string)
      sku     = optional(string, "Standard")
    }))

    # Private DNS Configuration
    private_dns = optional(object({
      enabled = optional(bool, false)
      zones   = optional(list(string), [])
      }), {
      enabled = false
      zones   = []
    })

    # Bastion Host Configuration (if configured, will be deployed)
    bastion = optional(object({
      enabled               = optional(bool, true)
      name                  = optional(string)
      subnet_address_prefix = string
      sku                   = optional(string, "Basic")
      zones                 = optional(list(string), [])
    }))

    # NAT Gateway Configuration
    nat_gateway = optional(object({
      enabled = optional(bool, false)
      name    = optional(string)
      zones   = optional(list(string), ["1", "2", "3"])
      public_ips = optional(object({
        count = optional(number, 1)
        sku   = optional(string, "Standard")
        }), {
        count = 1
        sku   = "Standard"
      })
      }), {
      enabled = false
      # name will be computed
      zones = ["1", "2", "3"]
      public_ips = {
        count = 1
        sku   = "Standard"
      }
    })
  })
  default = {
    enabled = true
    hub_virtual_network = {
      address_space = ["10.0.0.0/16"]
      subnets = {
        # Only custom subnets go here - special Azure subnets are created by ALZ components
        # Example:
        # "private-endpoints" = {
        #   address_prefixes = ["10.0.4.0/24"]
        #   service_endpoints = ["Microsoft.Storage"]
        # }
      }
    }
  }
}

# Identity Configuration
variable "identity_config" {
  description = "Configuration for identity resources"
  type = object({
    enabled             = optional(bool, false)
    resource_group_name = optional(string)

    # Virtual Network Configuration
    virtual_network = optional(object({
      name          = optional(string, null)
      address_space = list(string)
      subnets = map(object({
        address_prefixes = list(string)
      }))
    }))

    # Domain Controllers Configuration
    domain_controllers = optional(object({
      count                  = optional(number, 2)
      vm_size                = optional(string, "Standard_D2s_v5")
      os_sku                 = optional(string, "2022-standard")
      admin_username         = optional(string, "azureadmin")
      os_disk_size_gb        = optional(number, 128)
      data_disk_size_gb      = optional(number, 256)
      enable_disk_encryption = optional(bool, false)
      availability_zones     = optional(list(string), [])
      enable_backup          = optional(bool, false)
      static_ip_start        = optional(string, "10.1.1.10")

      # Domain Configuration
      domain_name              = optional(string, "example.local")
      domain_mode              = optional(string, "WinThreshold")
      forest_mode              = optional(string, "WinThreshold")
      safe_mode_admin_password = optional(string)
    }))

    # Key Vault Configuration
    enable_key_vault = optional(bool, true)
    key_vault_config = optional(object({
      sku_name                        = optional(string, "standard")
      enabled_for_disk_encryption     = optional(bool, true)
      enabled_for_deployment          = optional(bool, true)
      enabled_for_template_deployment = optional(bool, true)
      purge_protection_enabled        = optional(bool, false)

      # Network access configuration
      public_network_access_enabled = optional(bool, true)
      network_acls = optional(object({
        bypass                     = optional(string, "AzureServices")
        default_action             = optional(string, "Deny")
        ip_rules                   = optional(list(string), [])
        virtual_network_subnet_ids = optional(list(string), [])
        }), {
        bypass                     = "AzureServices"
        default_action             = "Deny"
        ip_rules                   = []
        virtual_network_subnet_ids = []
      })

      # Private endpoint configuration
      enable_private_endpoint    = optional(bool, false)
      private_endpoint_subnet_id = optional(string, null)
      }), {
      sku_name                        = "standard"
      enabled_for_disk_encryption     = true
      enabled_for_deployment          = true
      enabled_for_template_deployment = true
      purge_protection_enabled        = false
      public_network_access_enabled   = true
      network_acls = {
        bypass                     = "AzureServices"
        default_action             = "Deny"
        ip_rules                   = []
        virtual_network_subnet_ids = []
      }
      enable_private_endpoint    = false
      private_endpoint_subnet_id = null
    })

    # Virtual Machine Configuration (New flexible structure)
    deploy_virtual_machines = optional(bool, false)
    virtual_machines = optional(map(object({
      count              = optional(number, 1)
      vm_size            = optional(string, "Standard_D2s_v5")
      os_type            = optional(string, "Windows")
      os_sku             = optional(string, "2022-datacenter")
      admin_username     = optional(string, "azureadmin")
      os_disk_size_gb    = optional(number, 128)
      availability_zones = optional(list(string), ["1"])
      subnet_name        = string
      static_ip_start    = optional(string)
      enable_extensions  = optional(bool, true)
      vm_name_prefix     = optional(string)

      # Multiple NICs support
      network_interfaces = optional(list(object({
        subnet_name                   = string
        enable_ip_forwarding          = optional(bool, false)
        enable_accelerated_networking = optional(bool, false)
        private_ip_allocation_method  = optional(string, "Dynamic")
        static_ip_address             = optional(string)
        })), [{
        subnet_name = "default"
      }])

      # Multiple Data Disks support
      data_disks = optional(list(object({
        size_gb              = optional(number, 256)
        caching              = optional(string, "ReadWrite")
        storage_account_type = optional(string, "Premium_LRS")
        create_option        = optional(string, "Empty")
        lun                  = number
        })), [{
        size_gb = 256
        lun     = 0
      }])
    })), {})

    # Backup Configuration
    enable_backup = optional(bool, false)
    backup_policy = optional(object({
      backup_frequency = optional(string, "Daily")
      backup_time      = optional(string, "22:00")
      retention_days   = optional(number, 30)
    }))

    # Connectivity
    connect_to_hub = optional(bool, true)
  })
  default = {
    enabled        = false
    connect_to_hub = true
  }
}

# Individual Spoke Configurations
# Each spoke type has its own dedicated variable for explicit control

# Infrastructure Configuration
variable "infra_config" {
  description = "Configuration for infrastructure landing zone"
  type = object({
    enabled             = optional(bool, false)
    resource_group_name = optional(string)
    virtual_network = object({
      name          = optional(string, null)
      address_space = list(string)
      subnets = map(object({
        address_prefixes  = list(string)
        service_endpoints = optional(list(string), [])
      }))
    })
    connect_to_hub = optional(bool, true)
    enable_backup  = optional(bool, true)
    enable_storage = optional(bool, true)

    # Backup configuration
    backup_config = optional(object({
      sku                           = optional(string, "Standard")
      storage_mode_type             = optional(string, "LocallyRedundant")
      cross_region_restore_enabled  = optional(bool, false)
      public_network_access_enabled = optional(bool, true)
      immutability                  = optional(string, "Unlocked")

      backup_policy = optional(object({
        name            = optional(string, "DefaultBackupPolicy")
        policy_type     = optional(string, "V2")
        timezone        = optional(string, "UTC")
        frequency       = optional(string, "Daily")
        backup_time     = optional(string, "22:00")
        retention_daily = optional(number, 35)
      }))
    }))

    # Virtual machines configuration
    deploy_virtual_machines = optional(bool, false)
    virtual_machines = optional(map(object({
      count              = optional(number, 1)
      vm_size            = optional(string, "Standard_D2s_v5")
      os_type            = optional(string, "Windows")
      os_sku             = optional(string, "2022-datacenter")
      admin_username     = optional(string, "azureadmin")
      os_disk_size_gb    = optional(number, 128)
      availability_zones = optional(list(string), ["1"])
      subnet_name        = string
      static_ip_start    = optional(string)
      enable_extensions  = optional(bool, true)
      vm_name_prefix     = optional(string)

      network_interfaces = optional(list(object({
        subnet_name                   = string
        enable_ip_forwarding          = optional(bool, false)
        enable_accelerated_networking = optional(bool, false)
        private_ip_allocation_method  = optional(string, "Dynamic")
        static_ip_address             = optional(string)
        })), [{
        subnet_name = "default"
      }])

      data_disks = optional(list(object({
        size_gb              = optional(number, 256)
        caching              = optional(string, "ReadWrite")
        storage_account_type = optional(string, "Premium_LRS")
        lun                  = number
        })), [{
        size_gb = 256
        lun     = 0
      }])
    })), {})
  })
  default = null
}

# AVD Configuration
variable "avd_config" {
  description = "Configuration for Azure Virtual Desktop"
  type = object({
    enabled             = optional(bool, false)
    resource_group_name = optional(string)

    # Workspace Configuration
    workspace_name                = optional(string)
    workspace_friendly_name       = optional(string, "Azure Virtual Desktop")
    workspace_description         = optional(string, "Azure Virtual Desktop workspace")
    public_network_access_enabled = optional(bool, true)

    # Host Pool Configuration
    host_pool = optional(object({
      name                             = optional(string)
      friendly_name                    = optional(string, "AVD Host Pool")
      description                      = optional(string, "Azure Virtual Desktop Host Pool")
      type                             = optional(string, "Pooled")
      maximum_sessions_allowed         = optional(number, 50)
      load_balancer_type               = optional(string, "BreadthFirst")
      personal_desktop_assignment_type = optional(string)
      custom_rdp_properties            = optional(string, "drivestoredirect:s:;usbdevicestoredirect:s:*;redirectclipboard:i:1;redirectprinters:i:1;audiomode:i:0;videoplaybackmode:i:1;devicestoredirect:s:*;redirectcomports:i:0;redirectsmartcards:i:1;enablecredsspsupport:i:1;redirectwebauthn:i:1;use multimon:i:1;autoreconnection enabled:i:1;bandwidthautodetect:i:1;networkautodetect:i:1;audiocapturemode:i:1;encode redirected video capture:i:1;camerastoredirect:s:*;redirectlocation:i:1;keyboardhook:i:1;smart sizing:i:1;dynamic resolution:i:1;maximizetocurrentdisplays:i:1;singlemoninwindowedmode:i:1;screen mode id:i:2;enablerdsaadauth:i:1")
      start_vm_on_connect              = optional(bool, true)
      validate_environment             = optional(bool, false)
      }), {
      # name will be computed
      friendly_name            = "AVD Host Pool"
      description              = "Azure Virtual Desktop Host Pool"
      type                     = "Pooled"
      maximum_sessions_allowed = 50
      load_balancer_type       = "BreadthFirst"
      custom_rdp_properties    = "drivestoredirect:s:;usbdevicestoredirect:s:*;redirectclipboard:i:1;redirectprinters:i:1;audiomode:i:0;videoplaybackmode:i:1;devicestoredirect:s:*;redirectcomports:i:0;redirectsmartcards:i:1;enablecredsspsupport:i:1;redirectwebauthn:i:1;use multimon:i:1;autoreconnection enabled:i:1;bandwidthautodetect:i:1;networkautodetect:i:1;audiocapturemode:i:1;encode redirected video capture:i:1;camerastoredirect:s:*;redirectlocation:i:1;keyboardhook:i:1;smart sizing:i:1;dynamic resolution:i:1;maximizetocurrentdisplays:i:1;singlemoninwindowedmode:i:1;screen mode id:i:2;enablerdsaadauth:i:1"
      start_vm_on_connect      = true
      validate_environment     = false
    })

    # Application Group Configuration
    application_group = optional(object({
      name                         = optional(string)
      friendly_name                = optional(string, "AVD Desktop Application Group")
      description                  = optional(string, "Azure Virtual Desktop Desktop Application Group")
      type                         = optional(string, "Desktop")
      default_desktop_display_name = optional(string, "SessionDesktop")
      }), {
      # name will be computed
      friendly_name                = "AVD Desktop Application Group"
      description                  = "Azure Virtual Desktop Desktop Application Group"
      type                         = "Desktop"
      default_desktop_display_name = "SessionDesktop"
    })

    # Insights Configuration
    enable_insights = optional(bool, true)

    # FSLogix Configuration
    fslogix = optional(object({
      enabled                 = optional(bool, true)
      profile_share_size_gb   = optional(number, 100)
      container_share_size_gb = optional(number, 100)
      enable_private_endpoint = optional(bool, false)
      }), {
      enabled                 = true
      profile_share_size_gb   = 100
      container_share_size_gb = 100
      enable_private_endpoint = false
    })

    # Start VM on Connect RBAC Configuration
    enable_start_vm_rbac = optional(bool, true)

    # Scaling Plan Configuration
    enable_scaling_plan = optional(bool, false)
    scaling_plan = optional(object({
      name        = optional(string)
      description = optional(string, "Azure Virtual Desktop Scaling Plan")
      time_zone   = optional(string, "GMT Standard Time")
      schedules = optional(map(object({
        name                                 = string
        days_of_week                         = list(string)
        ramp_up_start_time                   = string
        ramp_up_load_balancing_algorithm     = string
        ramp_up_minimum_hosts_percent        = number
        ramp_up_capacity_threshold_percent   = number
        peak_start_time                      = string
        peak_load_balancing_algorithm        = string
        ramp_down_start_time                 = string
        ramp_down_load_balancing_algorithm   = string
        ramp_down_minimum_hosts_percent      = number
        ramp_down_capacity_threshold_percent = number
        ramp_down_force_logoff_users         = bool
        ramp_down_notification_message       = string
        ramp_down_stop_hosts_when            = string
        ramp_down_wait_time_minutes          = number
        off_peak_start_time                  = string
        off_peak_load_balancing_algorithm    = string
        })), {
        "weekdays" = {
          name                                 = "Weekdays"
          days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
          ramp_up_start_time                   = "09:00"
          ramp_up_load_balancing_algorithm     = "BreadthFirst"
          ramp_up_minimum_hosts_percent        = 20
          ramp_up_capacity_threshold_percent   = 60
          peak_start_time                      = "10:00"
          peak_load_balancing_algorithm        = "BreadthFirst"
          ramp_down_start_time                 = "18:00"
          ramp_down_load_balancing_algorithm   = "DepthFirst"
          ramp_down_minimum_hosts_percent      = 10
          ramp_down_capacity_threshold_percent = 90
          ramp_down_force_logoff_users         = false
          ramp_down_notification_message       = "You will be logged off in 30 min. Make sure to save your work."
          ramp_down_stop_hosts_when            = "ZeroSessions"
          ramp_down_wait_time_minutes          = 30
          off_peak_start_time                  = "20:00"
          off_peak_load_balancing_algorithm    = "DepthFirst"
        }
      })
      }), {
      # name will be computed
      description = "Azure Virtual Desktop Scaling Plan"
      time_zone   = "GMT Standard Time"
      schedules = {
        "weekdays" = {
          name                                 = "Weekdays"
          days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
          ramp_up_start_time                   = "09:00"
          ramp_up_load_balancing_algorithm     = "BreadthFirst"
          ramp_up_minimum_hosts_percent        = 20
          ramp_up_capacity_threshold_percent   = 60
          peak_start_time                      = "10:00"
          peak_load_balancing_algorithm        = "BreadthFirst"
          ramp_down_start_time                 = "18:00"
          ramp_down_load_balancing_algorithm   = "DepthFirst"
          ramp_down_minimum_hosts_percent      = 10
          ramp_down_capacity_threshold_percent = 90
          ramp_down_force_logoff_users         = false
          ramp_down_notification_message       = "You will be logged off in 30 min. Make sure to save your work."
          ramp_down_stop_hosts_when            = "ZeroSessions"
          ramp_down_wait_time_minutes          = 30
          off_peak_start_time                  = "20:00"
          off_peak_load_balancing_algorithm    = "DepthFirst"
        }
      }
    })

    # Network Configuration
    create_virtual_network = optional(bool, true)
    connect_to_hub         = optional(bool, true)
    virtual_network = optional(object({
      name          = optional(string)
      address_space = optional(list(string), ["10.100.0.0/16"])
      subnets = optional(map(object({
        address_prefixes  = list(string)
        service_endpoints = optional(list(string), [])
        })), {
        "avd_session_hosts" = {
          address_prefixes  = ["10.100.1.0/24"]
          service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
        }
      })
      }), {
      # name will be computed
      address_space = ["10.100.0.0/16"]
      subnets = {
        "avd_session_hosts" = {
          address_prefixes  = ["10.100.1.0/24"]
          service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
        }
      }
    })
  })
  default = {
    # resource_group_name will be computed
    # workspace_name will be computed
    workspace_friendly_name       = "Azure Virtual Desktop"
    workspace_description         = "Azure Virtual Desktop workspace"
    public_network_access_enabled = true
    host_pool = {
      # name will be computed
      friendly_name            = "AVD Host Pool"
      description              = "Azure Virtual Desktop Host Pool"
      type                     = "Pooled"
      maximum_sessions_allowed = 50
      load_balancer_type       = "BreadthFirst"
      custom_rdp_properties    = "drivestoredirect:s:;usbdevicestoredirect:s:*;redirectclipboard:i:1;redirectprinters:i:1;audiomode:i:0;videoplaybackmode:i:1;devicestoredirect:s:*;redirectcomports:i:0;redirectsmartcards:i:1;enablecredsspsupport:i:1;redirectwebauthn:i:1;use multimon:i:1;autoreconnection enabled:i:1;bandwidthautodetect:i:1;networkautodetect:i:1;audiocapturemode:i:1;encode redirected video capture:i:1;camerastoredirect:s:*;redirectlocation:i:1;keyboardhook:i:1;smart sizing:i:1;dynamic resolution:i:1;maximizetocurrentdisplays:i:1;singlemoninwindowedmode:i:1;screen mode id:i:2;enablerdsaadauth:i:1"
      start_vm_on_connect      = true
      validate_environment     = false
    }
    application_group = {
      # name will be computed
      friendly_name                = "AVD Desktop Application Group"
      description                  = "Azure Virtual Desktop Desktop Application Group"
      type                         = "Desktop"
      default_desktop_display_name = "SessionDesktop"
    }
    enable_insights = true
    fslogix = {
      enabled                 = true
      profile_share_size_gb   = 100
      container_share_size_gb = 100
      enable_private_endpoint = false
    }
    enable_scaling_plan = false
    scaling_plan = {
      # name will be computed
      description = "Azure Virtual Desktop Scaling Plan"
      time_zone   = "GMT Standard Time"
      schedules = {
        "weekdays" = {
          name                                 = "Weekdays"
          days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
          ramp_up_start_time                   = "09:00"
          ramp_up_load_balancing_algorithm     = "BreadthFirst"
          ramp_up_minimum_hosts_percent        = 20
          ramp_up_capacity_threshold_percent   = 60
          peak_start_time                      = "10:00"
          peak_load_balancing_algorithm        = "BreadthFirst"
          ramp_down_start_time                 = "18:00"
          ramp_down_load_balancing_algorithm   = "DepthFirst"
          ramp_down_minimum_hosts_percent      = 10
          ramp_down_capacity_threshold_percent = 90
          ramp_down_force_logoff_users         = false
          ramp_down_notification_message       = "You will be logged off in 30 min. Make sure to save your work."
          ramp_down_stop_hosts_when            = "ZeroSessions"
          ramp_down_wait_time_minutes          = 30
          off_peak_start_time                  = "20:00"
          off_peak_load_balancing_algorithm    = "DepthFirst"
        }
      }
    }
    create_virtual_network = true
    connect_to_hub         = true
    virtual_network = {
      # name will be computed
      address_space = ["10.100.0.0/16"]
      subnets = {
        "avd_session_hosts" = {
          address_prefixes  = ["10.100.1.0/24"]
          service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
        }
      }
    }
  }
}

# Azure Image Builder Configuration
variable "aib_config" {
  description = "Configuration for Azure Image Builder"
  type = object({
    enabled = optional(bool, false)

    # Resource naming
    resource_group_name   = optional(string)
    managed_identity_name = optional(string)
    gallery_name          = optional(string)
    api_version           = optional(string, "2023-07-01")

    # Storage configuration
    enable_file_share        = optional(bool, false)
    file_share_quota_gb      = optional(number, 100)
    enable_private_endpoints = optional(bool, false)

    # Replication settings
    replication_regions = optional(list(string), [])

    # Image configurations
    images = optional(map(object({
      # Image metadata
      name        = string
      description = optional(string, "Custom image built with Azure Image Builder")
      os_type     = optional(string, "Windows")

      # VM specifications
      vm_size               = optional(string, "Standard_E8as_v6")
      os_disk_size_gb       = optional(number, 127)
      build_timeout_minutes = optional(number, 300)

      # Image specifications
      hyper_v_generation          = optional(string, "V2")
      trusted_launch_supported    = optional(bool, true)
      enable_nvme_disk_controller = optional(bool, true)

      # Source image
      publisher = string
      offer     = string
      sku       = string
      version   = optional(string, "latest")

      # Customizations (AVD optimizations, custom scripts, etc.)
      customizations = optional(list(object({
        type           = string
        name           = string
        inline         = optional(list(string))
        scriptUri      = optional(string)
        destination    = optional(string)
        runElevated    = optional(bool, true)
        runAsSystem    = optional(bool, true)
        sha256Checksum = optional(string)
        searchCriteria = optional(string)
        filters        = optional(list(string))
        updateLimit    = optional(number)
        restartTimeout = optional(string)
      })), [])
      })), {
      "avd-win11-m365" = {
        name        = "avd-win11-m365"
        description = "Windows 11 Multi-session with Microsoft 365 Apps for AVD"
        os_type     = "Windows"

        vm_size               = "Standard_E8as_v6"
        os_disk_size_gb       = 127
        build_timeout_minutes = 300

        hyper_v_generation          = "V2"
        trusted_launch_supported    = true
        enable_nvme_disk_controller = true

        publisher = "MicrosoftWindowsDesktop"
        offer     = "office-365"
        sku       = "win11-24h2-avd-m365"
        version   = "latest"

        customizations = [
          {
            name           = "avdBuiltInScript_preWindowsUpdate"
            type           = "WindowsUpdate"
            searchCriteria = "IsInstalled=0"
            filters = [
              "exclude:$_.Title -like '*Preview*'",
              "exclude:$_.KBArticleIDs -Contains '5040442'",
              "include:$true"
            ]
            updateLimit = 20
          },
          {
            name           = "avdBuiltInScript_preWindowsUpdate-windowsRestart"
            type           = "WindowsRestart"
            restartTimeout = "10m"
          }
        ]
      }
    })
  })

  default = {
    # resource_group_name will be computed
    # managed_identity_name will be computed
    api_version              = "2023-07-01"
    enable_file_share        = false
    file_share_quota_gb      = 100
    enable_private_endpoints = false
    replication_regions      = []

    images = {
      "avd-win11-m365" = {
        name        = "avd-win11-m365"
        description = "Windows 11 Multi-session with Microsoft 365 Apps for AVD"
        os_type     = "Windows"

        vm_size               = "Standard_E8as_v6"
        os_disk_size_gb       = 127
        build_timeout_minutes = 300

        hyper_v_generation          = "V2"
        trusted_launch_supported    = true
        enable_nvme_disk_controller = true

        publisher = "MicrosoftWindowsDesktop"
        offer     = "office-365"
        sku       = "win11-24h2-avd-m365"
        version   = "latest"

        customizations = [
          {
            name           = "avdBuiltInScript_preWindowsUpdate"
            type           = "WindowsUpdate"
            searchCriteria = "IsInstalled=0"
            filters = [
              "exclude:$_.Title -like '*Preview*'",
              "exclude:$_.KBArticleIDs -Contains '5040442'",
              "include:$true"
            ]
            updateLimit = 20
          },
          {
            name           = "avdBuiltInScript_preWindowsUpdate-windowsRestart"
            type           = "WindowsRestart"
            restartTimeout = "10m"
          }
        ]
      }
    }
  }
}


# Network Access Configuration
variable "allow_list_ip" {
  description = "List of IP addresses to allow access to storage and other resources"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for ip in var.allow_list_ip : can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}(?:/[0-9]{1,2})?$", trimspace(ip)))
    ])
    error_message = "All entries in allow_list_ip must be valid IP addresses or CIDR blocks."
  }
}

# Tags
variable "default_tags" {
  description = "Default tags to apply to all resources. Must include Environment, Owner, and CostCenter."
  type        = map(string)

  validation {
    condition = (
      can(var.default_tags["Environment"]) &&
      can(var.default_tags["Owner"]) &&
      can(var.default_tags["CostCenter"]) &&
      contains(["Production", "Development", "Test", "Staging", "Demo"], var.default_tags["Environment"])
    )
    error_message = "default_tags must include 'Environment', 'Owner', and 'CostCenter'. Environment must be one of: Production, Development, Test, Staging, Demo."
  }

  validation {
    condition     = can(regex("^[A-Z][a-zA-Z0-9\\s-_]*$", var.default_tags["Owner"]))
    error_message = "Owner tag must start with uppercase letter and contain only letters, numbers, spaces, hyphens, and underscores."
  }
}

# IP Range Variables for Azure Firewall Rules
# These variables allow customization of firewall IP ranges
variable "hub_address_space" {
  description = "Address space for the hub network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "identity_spoke_address_space" {
  description = "Address space for the identity spoke network"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "infrastructure_spoke_address_space" {
  description = "Address space for the infrastructure spoke network"
  type        = list(string)
  default     = ["10.2.0.0/16"]
}

variable "avd_spoke_address_space" {
  description = "Address space for the AVD spoke network"
  type        = list(string)
  default     = ["10.3.0.0/16"]
}

variable "all_spoke_address_spaces" {
  description = "All spoke network address spaces"
  type        = list(string)
  default     = ["10.0.0.0/16", "10.1.0.0/16", "10.2.0.0/16", "10.3.0.0/16"]
}

variable "domain_controller_ips" {
  description = "IP addresses of domain controllers"
  type        = list(string)
  default     = ["10.1.1.10", "10.1.1.11"]
}

variable "specific_subnet_ranges" {
  description = "Specific subnet ranges for various services"
  type = object({
    bastion_subnet         = optional(string, "10.0.1.0/24")
    domain_subnets         = optional(list(string), ["10.1.1.0/24"])
    avd_session_hosts      = optional(list(string), ["10.3.1.0/24", "10.3.2.0/24", "10.3.3.0/24", "10.3.4.0/24", "10.3.5.0/24"])
    infrastructure_subnets = optional(list(string), ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"])
  })
  default = {
    bastion_subnet         = "10.0.1.0/24"
    domain_subnets         = ["10.1.1.0/24"]
    avd_session_hosts      = ["10.3.1.0/24", "10.3.2.0/24", "10.3.3.0/24", "10.3.4.0/24", "10.3.5.0/24"]
    infrastructure_subnets = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
  }
}

variable "external_service_ips" {
  description = "External service IP addresses"
  type = object({
    dns_servers       = optional(list(string), ["168.63.129.16"])
    stun_turn_main    = optional(string, "51.5.0.0/16")
    stun_turn_legacy  = optional(string, "20.202.0.0/16")
    external_services = optional(list(string), [])
  })
  default = {
    dns_servers       = ["168.63.129.16"] # Azure DNS
    stun_turn_main    = "51.5.0.0/16"
    stun_turn_legacy  = "20.202.0.0/16"
    external_services = []
  }
}

