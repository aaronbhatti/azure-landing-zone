# Variables for Azure Image Builder Module

variable "org_name" {
  description = "The name of the organization"
  type        = string
}

variable "environment" {
  description = "The environment name (e.g., dev, test, staging, prod)"
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
}


variable "subscription_id" {
  description = "The subscription ID where AIB resources will be deployed"
  type        = string
}

variable "enable_telemetry" {
  description = "Enable telemetry for the deployment"
  type        = bool
  default     = true
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "allow_list_ip" {
  description = "List of IP addresses to allow access to storage resources"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for ip in var.allow_list_ip : can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}(?:/[0-9]{1,2})?$", trimspace(ip)))
    ])
    error_message = "All entries in allow_list_ip must be valid IP addresses or CIDR blocks."
  }
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoints (required if enable_private_endpoints is true)"
  type        = string
  default     = null
}

variable "private_dns_zone_blob_id" {
  description = "Private DNS Zone ID for blob storage private endpoint"
  type        = string
  default     = null
}

variable "private_dns_zone_file_id" {
  description = "Private DNS Zone ID for file storage private endpoint"
  type        = string
  default     = null
}

variable "avd_network_resource_group_id" {
  description = "Resource ID of the AVD network resource group for Network Contributor role assignment"
  type        = string
  default     = null
}

variable "avd_vnet_id" {
  description = "Resource ID of the AVD virtual network for Network Contributor role assignment"
  type        = string
  default     = null
}

variable "build_subnet_id" {
  description = "Subnet ID for the AIB build VMs (if using vnetConfig)"
  type        = string
  default     = null
}

variable "aib_config" {
  description = "Configuration for Azure Image Builder"
  type = object({
    # Storage configuration
    enable_file_share        = optional(bool, false)
    file_share_quota_gb      = optional(number, 100)
    enable_private_endpoints = optional(bool, false)

    # Replication settings
    replication_regions = optional(list(string), [])

    # Image configurations
    images = map(object({
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
    }))
  })

  # Default configuration with minimal required values
  default = {
    enable_file_share        = false
    file_share_quota_gb      = 100
    enable_private_endpoints = false
    replication_regions      = []
    images                   = {}
  }
}
