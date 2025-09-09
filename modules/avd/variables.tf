variable "environment" {
  description = "The environment name (e.g., dev, test, staging, prod)"
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
}


variable "subscription_id" {
  description = "The subscription ID for the AVD resources"
  type        = string
}

variable "avd_config" {
  description = "Configuration for Azure Virtual Desktop"
  type = object({
    resource_group_name = optional(string, "rg-avd")


    # Workspace Configuration
    workspace_name                = optional(string, "avd-workspace")
    workspace_friendly_name       = optional(string, "Azure Virtual Desktop")
    workspace_description         = optional(string, "Azure Virtual Desktop workspace")
    public_network_access_enabled = optional(bool, true)

    # Host Pool Configuration
    host_pool = object({
      name                             = optional(string, "avd-hostpool")
      friendly_name                    = optional(string, "AVD Host Pool")
      description                      = optional(string, "Azure Virtual Desktop Host Pool")
      type                             = optional(string, "Pooled")
      maximum_sessions_allowed         = optional(number, 50)
      load_balancer_type               = optional(string, "BreadthFirst")
      personal_desktop_assignment_type = optional(string)
      custom_rdp_properties            = optional(string, "drivestoredirect:s:;usbdevicestoredirect:s:*;redirectclipboard:i:1;redirectprinters:i:1;audiomode:i:0;videoplaybackmode:i:1;devicestoredirect:s:*;redirectcomports:i:0;redirectsmartcards:i:1;enablecredsspsupport:i:1;redirectwebauthn:i:1;use multimon:i:1;autoreconnection enabled:i:1;bandwidthautodetect:i:1;networkautodetect:i:1;audiocapturemode:i:1;encode redirected video capture:i:1;camerastoredirect:s:*;redirectlocation:i:1;keyboardhook:i:1;smart sizing:i:1;dynamic resolution:i:1;maximizetocurrentdisplays:i:1;singlemoninwindowedmode:i:1;screen mode id:i:2;enablerdsaadauth:i:1")
      start_vm_on_connect              = optional(bool, true)
      validate_environment             = optional(bool, false)
    })

    # Application Group Configuration
    application_group = object({
      name                         = optional(string, "avd-appgroup")
      friendly_name                = optional(string, "AVD Desktop Application Group")
      description                  = optional(string, "Azure Virtual Desktop Desktop Application Group")
      type                         = optional(string, "Desktop")
      default_desktop_display_name = optional(string, "SessionDesktop")
    })

    # Insights Configuration
    enable_insights = optional(bool, true)

    # Scaling Plan Configuration (always created with sensible defaults)
    scaling_plan = optional(object({
      name      = optional(string)
      time_zone = optional(string, "GMT Standard Time")
      schedules = optional(map(object({
        days_of_week                         = list(string)
        off_peak_load_balancing_algorithm    = optional(string, "DepthFirst")
        off_peak_start_time                  = optional(string, "20:00")
        peak_load_balancing_algorithm        = optional(string, "DepthFirst")
        peak_start_time                      = optional(string, "08:00")
        ramp_down_capacity_threshold_percent = optional(number, 90)
        ramp_down_force_logoff_users         = optional(bool, false)
        ramp_down_load_balancing_algorithm   = optional(string, "DepthFirst")
        ramp_down_minimum_hosts_percent      = optional(number, 5)
        ramp_down_notification_message       = optional(string, "This desktop is shutting down in 15 minutes. Please save your work and logout.")
        ramp_down_start_time                 = optional(string, "19:00")
        ramp_down_stop_hosts_when            = optional(string, "ZeroActiveSessions")
        ramp_down_wait_time_minutes          = optional(number, 15)
        ramp_up_capacity_threshold_percent   = optional(number, 80)
        ramp_up_load_balancing_algorithm     = optional(string, "BreadthFirst")
        ramp_up_minimum_hosts_percent        = optional(number, 40)
        ramp_up_start_time                   = optional(string, "07:00")
        })), {
        "weekdays" = {
          days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
          off_peak_load_balancing_algorithm    = "DepthFirst"
          off_peak_start_time                  = "20:00"
          peak_load_balancing_algorithm        = "DepthFirst"
          peak_start_time                      = "08:00"
          ramp_down_capacity_threshold_percent = 90
          ramp_down_force_logoff_users         = false
          ramp_down_load_balancing_algorithm   = "DepthFirst"
          ramp_down_minimum_hosts_percent      = 5
          ramp_down_notification_message       = "This desktop is shutting down in 15 minutes. Please save your work and logout."
          ramp_down_start_time                 = "19:00"
          ramp_down_stop_hosts_when            = "ZeroActiveSessions"
          ramp_down_wait_time_minutes          = 15
          ramp_up_capacity_threshold_percent   = 80
          ramp_up_load_balancing_algorithm     = "BreadthFirst"
          ramp_up_minimum_hosts_percent        = 40
          ramp_up_start_time                   = "07:00"
        },
        "weekends" = {
          days_of_week                         = ["Saturday", "Sunday"]
          off_peak_load_balancing_algorithm    = "DepthFirst"
          off_peak_start_time                  = "19:00"
          peak_load_balancing_algorithm        = "DepthFirst"
          peak_start_time                      = "09:00"
          ramp_down_capacity_threshold_percent = 50
          ramp_down_force_logoff_users         = false
          ramp_down_load_balancing_algorithm   = "DepthFirst"
          ramp_down_minimum_hosts_percent      = 5
          ramp_down_notification_message       = "This desktop will be shutting down for maintenance in 15 minutes, please save your work and log out immediately."
          ramp_down_start_time                 = "18:00"
          ramp_down_stop_hosts_when            = "ZeroActiveSessions"
          ramp_down_wait_time_minutes          = 15
          ramp_up_capacity_threshold_percent   = 70
          ramp_up_load_balancing_algorithm     = "DepthFirst"
          ramp_up_minimum_hosts_percent        = 5
          ramp_up_start_time                   = "08:00"
        }
      })
      }), {
      # name will be computed
      time_zone = "GMT Standard Time"
      schedules = {
        "weekdays" = {
          days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
          off_peak_load_balancing_algorithm    = "DepthFirst"
          off_peak_start_time                  = "20:00"
          peak_load_balancing_algorithm        = "DepthFirst"
          peak_start_time                      = "08:00"
          ramp_down_capacity_threshold_percent = 90
          ramp_down_force_logoff_users         = false
          ramp_down_load_balancing_algorithm   = "DepthFirst"
          ramp_down_minimum_hosts_percent      = 5
          ramp_down_notification_message       = "This desktop is shutting down in 15 minutes. Please save your work and logout."
          ramp_down_start_time                 = "19:00"
          ramp_down_stop_hosts_when            = "ZeroActiveSessions"
          ramp_down_wait_time_minutes          = 15
          ramp_up_capacity_threshold_percent   = 80
          ramp_up_load_balancing_algorithm     = "BreadthFirst"
          ramp_up_minimum_hosts_percent        = 40
          ramp_up_start_time                   = "07:00"
        },
        "weekends" = {
          days_of_week                         = ["Saturday", "Sunday"]
          off_peak_load_balancing_algorithm    = "DepthFirst"
          off_peak_start_time                  = "19:00"
          peak_load_balancing_algorithm        = "DepthFirst"
          peak_start_time                      = "09:00"
          ramp_down_capacity_threshold_percent = 50
          ramp_down_force_logoff_users         = false
          ramp_down_load_balancing_algorithm   = "DepthFirst"
          ramp_down_minimum_hosts_percent      = 5
          ramp_down_notification_message       = "This desktop will be shutting down for maintenance in 15 minutes, please save your work and log out immediately."
          ramp_down_start_time                 = "18:00"
          ramp_down_stop_hosts_when            = "ZeroActiveSessions"
          ramp_down_wait_time_minutes          = 15
          ramp_up_capacity_threshold_percent   = 70
          ramp_up_load_balancing_algorithm     = "DepthFirst"
          ramp_up_minimum_hosts_percent        = 5
          ramp_up_start_time                   = "08:00"
        }
      }
    })

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

    # Role Assignments for Start VM on Connect
    enable_start_vm_rbac = optional(bool, true)

    # Network Configuration
    create_virtual_network = optional(bool, true)
    connect_to_hub         = optional(bool, true)
    existing_subnet_id     = optional(string, null)
    virtual_network = optional(object({
      name          = optional(string, "vnet-avd")
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
      name          = "vnet-avd"
      address_space = ["10.100.0.0/16"]
      subnets = {
        "avd_session_hosts" = {
          address_prefixes  = ["10.100.1.0/24"]
          service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
        }
      }
    })
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

variable "firewall_private_ip" {
  description = "The private IP address of the Azure Firewall (if enabled)"
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID from management subscription for centralized logging and AVD insights"
  type        = string
  default     = null
}

variable "hub_virtual_network_id" {
  description = "The ID of the hub virtual network for peering"
  type        = string
  default     = null
}

variable "hub_virtual_network_name" {
  description = "The name of the hub virtual network"
  type        = string
  default     = null
}

variable "hub_resource_group_name" {
  description = "The name of the hub resource group"
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

variable "dns_servers" {
  description = "DNS servers to configure for the virtual network. If contains 'firewall', it will be replaced with firewall private IP."
  type        = list(string)
  default     = ["168.63.129.16"] # Azure default DNS
}
