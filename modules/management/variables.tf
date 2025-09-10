# Management Module Variables - ALZ Management Resources

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_telemetry" {
  description = "Enable telemetry for the module"
  type        = bool
  default     = true
}

variable "enable_automation_account" {
  description = "Enable deployment of Azure Automation Account"
  type        = bool
  default     = true
}

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

