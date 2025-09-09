# Core Module Variables - ALZ Governance with Enhanced Archetype Overrides

variable "core_config" {
  description = "Configuration for ALZ core governance (management groups, policies, etc.)"
  type = object({
    # Enable/disable core governance deployment
    enabled = optional(bool, true)
    # Management Group Configuration
    management_group_display_name = optional(string, "Azure Landing Zones")
    management_group_id           = optional(string, "alz")
    management_group_parent_id    = optional(string)

    # Policy Configuration  
    enable_policy_assignments = optional(bool, true)
    policy_default_values     = optional(map(any), {})

    # Enhanced Enterprise Archetype Configuration with Security-First Approach
    archetypes = optional(map(object({
      policy_assignments     = optional(list(string), [])
      policy_definitions     = optional(list(string), [])
      policy_set_definitions = optional(list(string), [])
      role_definitions       = optional(list(string), [])
      archetype_config = optional(object({
        parameters = optional(map(object({
          value = any
        })), {})
        access_control = optional(map(list(string)), {})
        }), {
        parameters     = {}
        access_control = {}
      })
    })), {})




    # Security Configuration
    security_contact_email = optional(string, null)
  })

  default = {
    enabled                       = true
    management_group_display_name = "Azure Landing Zones"
    management_group_id           = "alz"
    enable_policy_assignments     = true
    policy_default_values         = {}
    archetypes                    = {}
    security_contact_email        = null
  }
}

variable "management_subscription_id" {
  description = "Subscription ID for management resources"
  type        = string
}

variable "connectivity_subscription_id" {
  description = "Subscription ID for connectivity resources"
  type        = string
}

variable "identity_subscription_id" {
  description = "Subscription ID for identity resources (optional)"
  type        = string
  default     = null
}

variable "avd_subscription_id" {
  description = "Subscription ID for AVD resources (optional)"
  type        = string
  default     = null
}

variable "infra_subscription_id" {
  description = "Subscription ID for infrastructure resources (optional)"
  type        = string
  default     = null
}

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

variable "dependencies" {
  description = "Dependencies to ensure proper deployment order for policy assignments"
  type = object({
    policy_assignments = optional(list(any), [])
  })
  default = {
    policy_assignments = []
  }
}

variable "enable_telemetry" {
  description = "Enable telemetry for the module"
  type        = bool
  default     = true
}