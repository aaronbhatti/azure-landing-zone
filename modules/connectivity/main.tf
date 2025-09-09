# Connectivity Module - Hub and Spoke networking using ALZ Pattern


# Local values for VPN Gateway configuration
locals {
  # Determine if VPN Gateway SKU supports/requires Active-Active mode
  # AZ variants (zone-redundant) typically support active-active
  active_active_skus = [
    "VpnGw1AZ", "VpnGw2AZ", "VpnGw3AZ", "VpnGw4AZ", "VpnGw5AZ",
    "VpnGw1", "VpnGw2", "VpnGw3", "VpnGw4", "VpnGw5" # Standard SKUs that support active-active
  ]

  is_active_active_sku = var.connectivity_config.vpn_gateway != null ? (
    contains(local.active_active_skus, var.connectivity_config.vpn_gateway.sku) &&
    try(var.connectivity_config.vpn_gateway.enable_active_active, true) # Default to active-active for supported SKUs
  ) : false
}


resource "modtm_telemetry" "connectivity" {
  count = var.enable_telemetry ? 1 : 0

  tags = local.connectivity_tags
}

# Connectivity Resource Group using AVM Resource Group Module
module "connectivity_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = ">= 0.1.0, < 1.0.0"

  providers = {
    azurerm = azurerm.connectivity
  }

  name     = local.connectivity_names.resource_group
  location = var.location
  tags     = local.connectivity_tags

  enable_telemetry = var.enable_telemetry
}

# Network Security Group for Hub regular subnets (non-special subnets)
resource "azurerm_network_security_group" "hub_nsg" {
  provider            = azurerm.connectivity
  name                = "nsg-${local.env_prefix}-hub-${local.location_abbr}"
  location            = var.location
  resource_group_name = module.connectivity_resource_group.resource.name

  # Basic allow rules for hub connectivity
  security_rule {
    name                       = "AllowVnetInBound"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowVnetOutBound"
    priority                   = 1000
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  tags = local.connectivity_tags
}

# Firewall policy will be created by the ALZ module

# ALZ Hub and Spoke Connectivity using AVM Pattern Module
module "alz_connectivity" {
  source  = "Azure/avm-ptn-alz-connectivity-hub-and-spoke-vnet/azurerm"
  version = "~> 0.11.3"

  providers = {
    azurerm = azurerm.connectivity
  }

  # Enable telemetry
  enable_telemetry = var.enable_telemetry

  # Shared settings across all hubs
  hub_and_spoke_networks_settings = var.connectivity_config.ddos_protection.enabled ? {
    ddos_protection_plan = {
      enabled             = true
      name                = local.connectivity_names.ddos_plan
      resource_group_name = module.connectivity_resource_group.resource.name
      location            = var.location
    }
  } : {}

  # Hub virtual networks configuration
  hub_virtual_networks = {
    "prod-hub" = {
      # Hub VNet Configuration
      hub_virtual_network = {
        name                            = local.connectivity_names.virtual_network
        resource_group_name             = module.connectivity_resource_group.resource.name
        resource_group_creation_enabled = false # Use existing resource group
        location                        = var.location
        address_space                   = var.connectivity_config.hub_virtual_network.address_space

        # Custom route table names following naming standards
        route_table_name_firewall     = local.connectivity_names.firewall_route_table
        route_table_name_user_subnets = local.connectivity_names.default_route_table

        # Custom route table entries removed - ALZ module creates default routes automatically

        # Only include custom subnets - ALZ module creates special Azure subnets automatically
        subnets = {
          for k, v in var.connectivity_config.hub_virtual_network.subnets : k => {
            name                               = k
            address_prefixes                   = v.address_prefixes
            service_endpoints                  = try(v.service_endpoints, [])
            delegations                        = try(v.delegations, [])
            network_security_group_resource_id = azurerm_network_security_group.hub_nsg.id
          } if !contains(["GatewaySubnet", "AzureBastionSubnet", "AzureFirewallSubnet", "AzureFirewallManagementSubnet"], k)
        }

        # Enhanced Azure Firewall with WAF-aligned security  
        firewall = var.connectivity_config.firewall != null ? {
          enabled               = true
          sku_name              = var.connectivity_config.firewall.sku_name
          sku_tier              = var.connectivity_config.firewall.sku_tier
          subnet_address_prefix = var.connectivity_config.hub_virtual_network.subnets["AzureFirewallSubnet"].address_prefixes[0]
          name                  = local.connectivity_names.firewall

          # WAF-aligned firewall settings
          threat_intel_mode = "Alert" # Enable threat intelligence
          dns_servers       = []      # Use Azure DNS by default
          dns_proxy_enabled = true    # Enable DNS proxy for FQDN support in network rules
          private_ip_ranges = ["10.0.0.0/16", "10.1.0.0/16", "10.2.0.0/16", "10.3.0.0/16"]

          # Disable management IP and subnet (not needed for Standard SKU)
          management_ip_enabled = false

          # Default IP configuration for Azure Firewall
          default_ip_configuration = {
            name = "firewall-ip-config"
            public_ip_config = {
              name              = local.connectivity_names.firewall_pip
              allocation_method = "Static"
              sku               = "Standard"
              sku_tier          = "Regional"
              zones             = ["1", "2", "3"] # Multi-zone for high availability
            }
          }

          # Firewall policy configuration - let ALZ module create the policy
          firewall_policy = {
            name                     = local.connectivity_names.firewall_policy
            threat_intelligence_mode = var.connectivity_config.firewall.policy.threat_intelligence_mode
            dns = {
              servers       = var.connectivity_config.firewall.policy.dns.servers
              proxy_enabled = true
            }
          }
        } : null
      }

      # Virtual Network Gateways configuration
      virtual_network_gateways = {
        subnet_address_prefix = var.connectivity_config.vpn_gateway != null ? var.connectivity_config.hub_virtual_network.subnets["GatewaySubnet"].address_prefixes[0] : null
        vpn = var.connectivity_config.vpn_gateway != null && var.connectivity_config.vpn_gateway.enabled ? {
          enabled  = true
          name     = try(var.connectivity_config.vpn_gateway.name, local.connectivity_names.vpn_gateway)
          sku      = var.connectivity_config.vpn_gateway.sku
          location = var.location
          type     = var.connectivity_config.vpn_gateway.type

          # Dynamic IP configuration based on SKU type
          # Active-Active SKUs (AZ variants) get 2 IPs, Standard SKUs get 1 IP
          ip_configurations = local.is_active_active_sku ? {
            "01" = {
              name                          = "vnet-gateway-ip-config-01"
              subnet_id                     = null # Will be set by module
              private_ip_address_allocation = "Dynamic"
              public_ip_address = {
                name              = "${local.connectivity_names.vpn_gateway}-pip-01"
                allocation_method = "Static"
                sku               = "Standard"
                sku_tier          = "Regional"
                zones             = try(var.connectivity_config.vpn_gateway.zones, [])
              }
            }
            "02" = {
              name                          = "vnet-gateway-ip-config-02"
              subnet_id                     = null # Will be set by module
              private_ip_address_allocation = "Dynamic"
              public_ip_address = {
                name              = "${local.connectivity_names.vpn_gateway}-pip-02"
                allocation_method = "Static"
                sku               = "Standard"
                sku_tier          = "Regional"
                zones             = try(var.connectivity_config.vpn_gateway.zones, [])
              }
            }
            } : {
            "01" = {
              name                          = "vnet-gateway-ip-config"
              subnet_id                     = null # Will be set by module
              private_ip_address_allocation = "Dynamic"
              public_ip_address = {
                name              = "${local.connectivity_names.vpn_gateway}-pip"
                allocation_method = "Static"
                sku               = "Standard"
                sku_tier          = "Regional"
                zones             = try(var.connectivity_config.vpn_gateway.zones, [])
              }
            }
          }
          } : {
          enabled           = false
          name              = null
          sku               = null
          location          = null
          type              = null
          ip_configurations = {}
        }
        express_route = var.connectivity_config.expressroute_gateway != null && var.connectivity_config.expressroute_gateway.enabled ? {
          enabled  = true
          name     = try(var.connectivity_config.expressroute_gateway.name, local.connectivity_names.er_gateway)
          sku      = var.connectivity_config.expressroute_gateway.sku
          location = var.location
          } : {
          enabled = false
        }
      }

      # Private DNS Zones (optional)
      private_dns_zones = {
        enabled = var.connectivity_config.private_dns.enabled
        dns_zones = var.connectivity_config.private_dns.enabled ? {
          resource_group_name = module.connectivity_resource_group.resource.name
          private_link_private_dns_zones = {
            for zone in var.connectivity_config.private_dns.zones : zone => {
              zone_name = zone
            }
          }
          } : {
          resource_group_name            = null
          private_link_private_dns_zones = {}
        }
        auto_registration_zone_enabled = false
      }

      # Bastion Host (if enabled)
      bastion = var.connectivity_config.bastion != null && var.connectivity_config.bastion.enabled ? {
        enabled               = true
        subnet_address_prefix = var.connectivity_config.bastion.subnet_address_prefix
        bastion_host = {
          name  = local.connectivity_names.bastion_host
          sku   = var.connectivity_config.bastion.sku
          zones = contains(["Developer", "Basic"], var.connectivity_config.bastion.sku) ? [] : var.connectivity_config.bastion.zones
        }
        bastion_public_ip = {
          name              = "pip-bas-${local.env_prefix}-${local.hub_service}-${local.location_abbr}"
          allocation_method = "Static"
          sku               = "Standard"
          zones             = contains(["Developer", "Basic"], var.connectivity_config.bastion.sku) ? [] : var.connectivity_config.bastion.zones
        }
      } : null
    }
  }

  # Apply tags
  tags = merge(var.default_tags, {
    Workload = "Connectivity"
  })
}

# NAT Gateway for Azure Firewall Subnet
module "nat_gateway" {
  count = var.connectivity_config.nat_gateway != null && var.connectivity_config.nat_gateway.enabled ? 1 : 0

  source  = "Azure/avm-res-network-natgateway/azurerm"
  version = "~> 0.2.1"

  providers = {
    azurerm = azurerm.connectivity
  }

  name                = local.connectivity_names.nat_gateway
  location            = var.location
  resource_group_name = module.connectivity_resource_group.resource.name
  zones               = var.connectivity_config.nat_gateway.zones

  # Public IPs for NAT Gateway
  public_ips = {
    for i in range(var.connectivity_config.nat_gateway.public_ips.count) :
    "pip_${format("%02d", i + 1)}" => {
      name = "${local.connectivity_names.nat_gateway_pip}-${format("%02d", i + 1)}"
      sku  = var.connectivity_config.nat_gateway.public_ips.sku
    }
  }

  # NAT gateway association with Azure Firewall subnet
  subnet_associations = var.connectivity_config.firewall != null ? {
    "AzureFirewallSubnet" = {
      resource_id = "${module.alz_connectivity.virtual_network_resource_ids["prod-hub"]}/subnets/AzureFirewallSubnet"
    }
  } : {}

  # Tags
  tags = merge(var.default_tags, {
    Workload = "Connectivity"
  })

}



# Firewall Policy Rule Collection Groups (deployed separately after firewall policy)
resource "azurerm_firewall_policy_rule_collection_group" "default_application_rules" {
  count = var.connectivity_config.firewall != null ? 1 : 0

  name               = "DefaultApplicationRuleCollectionGroup"
  firewall_policy_id = "/subscriptions/${var.subscription_id}/resourceGroups/${module.connectivity_resource_group.resource.name}/providers/Microsoft.Network/firewallPolicies/${local.connectivity_names.firewall_policy}"
  priority           = 300

  dynamic "application_rule_collection" {
    for_each = local.merged_application_rules
    content {
      name     = application_rule_collection.value.name
      priority = application_rule_collection.value.priority
      action   = application_rule_collection.value.action

      dynamic "rule" {
        for_each = application_rule_collection.value.rules
        content {
          name        = rule.value.name
          description = try(rule.value.description, null)

          dynamic "protocols" {
            for_each = rule.value.protocols
            content {
              type = protocols.value.type
              port = protocols.value.port
            }
          }

          source_addresses  = try(rule.value.source_addresses, [])
          source_ip_groups  = try(rule.value.source_ip_groups, [])
          destination_fqdns = try(rule.value.destination_fqdns, [])
          destination_urls  = try(rule.value.destination_urls, [])
          web_categories    = try(rule.value.web_categories, [])
        }
      }
    }
  }

  depends_on = [
    module.alz_connectivity
  ]
}

resource "azurerm_firewall_policy_rule_collection_group" "default_network_rules" {
  count = var.connectivity_config.firewall != null ? 1 : 0

  name               = "DefaultNetworkRuleCollectionGroup"
  firewall_policy_id = "/subscriptions/${var.subscription_id}/resourceGroups/${module.connectivity_resource_group.resource.name}/providers/Microsoft.Network/firewallPolicies/${local.connectivity_names.firewall_policy}"
  priority           = 200

  dynamic "network_rule_collection" {
    for_each = local.merged_network_rules
    content {
      name     = network_rule_collection.value.name
      priority = network_rule_collection.value.priority
      action   = network_rule_collection.value.action

      dynamic "rule" {
        for_each = network_rule_collection.value.rules
        content {
          name                  = rule.value.name
          description           = try(rule.value.description, null)
          protocols             = rule.value.protocols
          source_addresses      = try(rule.value.source_addresses, [])
          source_ip_groups      = try(rule.value.source_ip_groups, [])
          destination_addresses = try(rule.value.destination_addresses, [])
          destination_ip_groups = try(rule.value.destination_ip_groups, [])
          destination_fqdns     = try(rule.value.destination_fqdns, [])
          destination_ports     = rule.value.destination_ports
        }
      }
    }
  }

  depends_on = [
    module.alz_connectivity
  ]
}
