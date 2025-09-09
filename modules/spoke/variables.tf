variable "environment" {
  description = "The environment name (e.g., dev, test, staging, prod)"
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
}

variable "subscription_id" {
  description = "The subscription ID for the spoke resources"
  type        = string
}

variable "workload_role" {
  description = "The role/purpose of this spoke (identity, infra, app, data, etc.)"
  type        = string

  validation {
    condition = contains([
      "identity",
      "infra",
      "app",
      "data",
      "security",
      "management",
      "dev",
      "test",
      "workload",
      "shared-services",
      "platform",
      "monitoring",
      "backup",
      "networking"
    ], var.workload_role)
    error_message = "workload_role must be one of: identity, infra, app, data, security, management, dev, test, workload, shared-services, platform, monitoring, backup, networking"
  }
}

variable "spoke_config" {
  description = "Configuration for the landing zone spoke"
  type = object({
    resource_group_name = optional(string)

    # Virtual Network Configuration
    virtual_network = optional(object({
      name          = string
      address_space = list(string)
      subnets = map(object({
        address_prefixes  = list(string)
        service_endpoints = optional(list(string), [])
      }))
    }))

    # Connectivity Options
    connect_to_hub = optional(bool, true)

    # Security Configuration
    security_rules = optional(map(object({
      name                       = string
      priority                   = number
      direction                  = string
      access                     = string
      protocol                   = string
      source_port_range          = optional(string, "*")
      destination_port_range     = optional(string)
      destination_port_ranges    = optional(list(string))
      source_address_prefix      = optional(string)
      source_address_prefixes    = optional(list(string))
      destination_address_prefix = optional(string, "*")
    })), {})

    # Note: NSG rule priorities are now hardcoded in main.tf for simplicity
    # Standard Azure NSG priorities: 100-4096 (lower number = higher priority)

    # Storage Configuration
    enable_storage = optional(bool, true)
    storage_config = optional(object({
      account_tier             = optional(string, "Standard")
      account_replication_type = optional(string, "LRS")
      account_kind             = optional(string, "StorageV2")
      }), {
      account_tier             = "Standard"
      account_replication_type = "LRS"
      account_kind             = "StorageV2"
    })

    # Enhanced Backup Configuration with AVM RSV module support
    enable_backup = optional(bool, true)

    # Azure Site Recovery Configuration (for DR environments)
    enable_asr = optional(bool, false)

    backup_config = optional(object({
      # Basic vault settings
      sku                           = optional(string, "Standard")
      storage_mode_type             = optional(string, "LocallyRedundant")
      cross_region_restore_enabled  = optional(bool, false)
      public_network_access_enabled = optional(bool, true)
      immutability                  = optional(string, "Unlocked")

      # Enhanced backup policy configuration
      backup_policy = optional(object({
        name            = optional(string, "DefaultBackupPolicy")
        policy_type     = optional(string, "V2")
        timezone        = optional(string, "UTC")
        frequency       = optional(string, "Daily")
        backup_time     = optional(string, "22:00")
        retention_daily = optional(number, 35)
        retention_weekly = optional(object({
          count    = optional(number, 12)
          weekdays = optional(list(string), ["Sunday"])
        }))
        retention_monthly = optional(object({
          count    = optional(number, 12)
          weekdays = optional(list(string), ["Sunday"])
          weeks    = optional(list(string), ["First"])
        }))
        retention_yearly = optional(object({
          count    = optional(number, 7)
          weekdays = optional(list(string), ["Sunday"])
          weeks    = optional(list(string), ["First"])
          months   = optional(list(string), ["January"])
        }))
      }))
    }))

    # Key Vault Configuration
    enable_key_vault = optional(bool, false)
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
    }))

    # Virtual Machine Configuration
    deploy_virtual_machines = optional(bool, false)
    virtual_machines = optional(map(object({
      count              = optional(number, 1)
      vm_size            = optional(string, "Standard_D2s_v5")
      os_type            = optional(string, "Windows")
      os_sku             = optional(string, "2022-datacenter")
      admin_username     = optional(string, "azureadmin")
      os_disk_size_gb    = optional(number, 128)
      availability_zones = optional(list(string), ["1"]) # Support multiple zones
      subnet_name        = string
      static_ip_start    = optional(string)
      enable_extensions  = optional(bool, true)
      vm_name_prefix     = optional(string) # Custom VM name prefix

      # Multiple NICs support with incremental naming
      network_interfaces = optional(list(object({
        subnet_name                   = string
        enable_ip_forwarding          = optional(bool, false)
        enable_accelerated_networking = optional(bool, false)
        private_ip_allocation_method  = optional(string, "Dynamic")
        static_ip_address             = optional(string)
        })), [{
        subnet_name = "default" # Will use subnet_name if not overridden
      }])

      # Multiple Data Disks support with incremental naming
      data_disks = optional(list(object({
        size_gb                   = optional(number, 256)
        caching                   = optional(string, "ReadWrite")
        storage_account_type      = optional(string, "Premium_LRS")
        create_option             = optional(string, "Empty")
        lun                       = number
        disk_encryption_set_id    = optional(string)      # For customer-managed keys
        write_accelerator_enabled = optional(bool, false) # For M-series VMs
        })), [{
        size_gb = 256
        lun     = 0
      }])
    })), {})

    # Role-specific configurations
    role_specific_config = optional(map(any), {})
  })
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
}

variable "enable_telemetry" {
  description = "Enable telemetry for the deployment"
  type        = bool
  default     = true
}

variable "hub_virtual_network_id" {
  description = "The ID of the hub virtual network for peering"
  type        = string
}

variable "hub_virtual_network_name" {
  description = "The name of the hub virtual network"
  type        = string
}

variable "hub_resource_group_name" {
  description = "The name of the hub resource group"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace for diagnostics"
  type        = string
  default     = null
}

variable "dns_servers" {
  description = "DNS servers to configure for the virtual network. If contains 'firewall', it will be replaced with firewall private IP."
  type        = list(string)
  default     = ["168.63.129.16"] # Azure default DNS
}

variable "firewall_private_ip" {
  description = "The private IP address of the Azure Firewall (used when dns_servers contains 'firewall')"
  type        = string
  default     = null
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


