variable "environment" {
  description = "The environment name (e.g., dev, test, staging, prod)"
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
}


variable "subscription_id" {
  description = "The subscription ID for the connectivity resources"
  type        = string
}

# IP Range Variables for Firewall Rules
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
    dns_servers       = ["168.63.129.16"] # Azure DNS from prod.tfvars
    stun_turn_main    = "51.5.0.0/16"
    stun_turn_legacy  = "20.202.0.0/16"
    external_services = []
  }
}

variable "connectivity_config" {
  description = "Configuration for ALZ hub and spoke connectivity resources"
  type = object({
    resource_group_name = optional(string, "rg-connectivity")

    # Hub Virtual Network Configuration
    hub_virtual_network = object({
      name          = optional(string, "vnet-hub")
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
      name     = optional(string, "fw-hub")
      sku_name = optional(string, "AZFW_VNet")
      sku_tier = optional(string, "Standard")

      # Firewall Policy Configuration with default rules
      policy = optional(object({
        name                     = optional(string, "fwpol-hub")
        threat_intelligence_mode = optional(string, "Alert")
        dns = optional(object({
          servers       = optional(list(string), [])
          proxy_enabled = optional(bool, true)
          }), {
          servers       = []
          proxy_enabled = true
        })

        # Application Rule Collections
        application_rule_collections = optional(list(object({
          name     = string
          priority = number
          action   = string
          rules = list(object({
            name        = string
            description = optional(string)
            protocols = list(object({
              type = string
              port = number
            }))
            source_addresses      = optional(list(string), [])
            source_ip_groups      = optional(list(string), [])
            destination_addresses = optional(list(string), [])
            destination_ip_groups = optional(list(string), [])
            destination_fqdns     = optional(list(string), [])
            destination_urls      = optional(list(string), [])
            fqdn_tags             = optional(list(string), [])
            web_categories        = optional(list(string), [])
          }))
        })), null)

        # Network Rule Collections  
        network_rule_collections = optional(list(object({
          name     = string
          priority = number
          action   = string
          rules = list(object({
            name                  = string
            description           = optional(string)
            protocols             = list(string)
            source_addresses      = optional(list(string), [])
            source_ip_groups      = optional(list(string), [])
            destination_addresses = optional(list(string), [])
            destination_ip_groups = optional(list(string), [])
            destination_fqdns     = optional(list(string), [])
            destination_ports     = list(string)
          }))
        })), null)
        }), {
        # name will be computed
        threat_intelligence_mode = "Alert"
        dns = {
          servers       = []
          proxy_enabled = true
        }
        application_rule_collections = null
        network_rule_collections     = null
      })
    }))

    # VPN Gateway Configuration
    vpn_gateway = optional(object({
      enabled  = optional(bool, false)
      name     = optional(string, "vgw-hub")
      type     = optional(string, "Vpn")
      vpn_type = optional(string, "RouteBased")
      sku      = optional(string, "VpnGw1")
      }), {
      enabled  = false
      name     = "vgw-hub"
      type     = "Vpn"
      vpn_type = "RouteBased"
      sku      = "VpnGw1"
    })

    # ExpressRoute Gateway Configuration
    expressroute_gateway = optional(object({
      enabled = optional(bool, false)
      name    = optional(string, "ergw-hub")
      sku     = optional(string, "Standard")
      }), {
      enabled = false
      name    = "ergw-hub"
      sku     = "Standard"
    })

    # Private DNS Configuration
    private_dns = optional(object({
      enabled = optional(bool, false)
      zones   = optional(list(string), [])
      }), {
      enabled = false
      zones   = []
    })

    # Bastion Host Configuration
    bastion = optional(object({
      enabled               = optional(bool, true)
      name                  = optional(string, "bas-hub")
      subnet_address_prefix = string
      sku                   = optional(string, "Standard")
      zones                 = optional(list(string), ["1", "2", "3"])
    }))

    # NAT Gateway Configuration
    nat_gateway = optional(object({
      enabled = optional(bool, false)
      name    = optional(string, "natgw-hub")
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
      name    = "natgw-hub"
      zones   = ["1", "2", "3"]
      public_ips = {
        count = 1
        sku   = "Standard"
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

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace for diagnostics"
  type        = string
}
