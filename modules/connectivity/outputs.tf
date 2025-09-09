# Resource Group Information
output "resource_group_id" {
  description = "The ID of the connectivity resource group"
  value       = module.connectivity_resource_group.resource.id
}

output "resource_group_name" {
  description = "The name of the connectivity resource group"
  value       = module.connectivity_resource_group.resource.name
}

output "hub_resource_group_name" {
  description = "The name of the hub resource group (alias for compatibility)"
  value       = module.connectivity_resource_group.resource.name
}

# Hub Virtual Network Information
output "hub_virtual_network_id" {
  description = "The ID of the hub virtual network"
  value       = module.alz_connectivity.virtual_network_resource_ids["prod-hub"]
}

output "hub_virtual_network_name" {
  description = "The name of the hub virtual network"
  value       = module.alz_connectivity.virtual_network_resource_names["prod-hub"]
}

output "hub_subnets" {
  description = "The hub subnets information"
  value       = module.alz_connectivity.virtual_network_resource_ids
}

# Azure Firewall Information
output "firewall_id" {
  description = "The ID of the Azure Firewall"
  value       = var.connectivity_config.firewall != null ? try(module.alz_connectivity.firewall_resource_ids["prod-hub"], null) : null
}

output "firewall_name" {
  description = "The name of the Azure Firewall"
  value       = var.connectivity_config.firewall != null ? try(module.alz_connectivity.firewall_resource_names["prod-hub"], null) : null
}

output "firewall_private_ip" {
  description = "The private IP address of the Azure Firewall"
  value       = var.connectivity_config.firewall != null ? try(module.alz_connectivity.firewall_private_ip_addresses["prod-hub"], null) : null
}

output "firewall_public_ip" {
  description = "The public IP address of the Azure Firewall"
  value       = var.connectivity_config.firewall != null ? try(module.alz_connectivity.firewall_public_ip_addresses["prod-hub"], null) : null
}

output "firewall_policy_id" {
  description = "The ID of the Azure Firewall Policy"
  value       = var.connectivity_config.firewall != null ? "/subscriptions/${var.subscription_id}/resourceGroups/${module.connectivity_resource_group.resource.name}/providers/Microsoft.Network/firewallPolicies/${local.connectivity_names.firewall_policy}" : null
}

output "firewall_policy_name" {
  description = "The name of the Azure Firewall Policy"
  value       = var.connectivity_config.firewall != null ? local.connectivity_names.firewall_policy : null
}

# VPN Gateway Information
output "vpn_gateway_id" {
  description = "The ID of the VPN Gateway"
  value       = var.connectivity_config.vpn_gateway != null ? try(module.alz_connectivity.virtual_network_gateways["prod-hub"].vpn.id, null) : null
}

output "vpn_gateway_name" {
  description = "The name of the VPN Gateway"
  value       = var.connectivity_config.vpn_gateway != null ? "${var.connectivity_config.vpn_gateway.name}-${var.environment}" : null
}

output "vpn_gateway_public_ip" {
  description = "The public IP address of the VPN Gateway"
  value       = var.connectivity_config.vpn_gateway != null ? try(module.alz_connectivity.virtual_network_gateways["prod-hub"].vpn.public_ip, null) : null
}

output "vpn_gateway_enabled" {
  description = "Whether VPN Gateway is configured and deployed"
  value       = var.connectivity_config.vpn_gateway != null
}

# ExpressRoute Gateway Information
output "expressroute_gateway_id" {
  description = "The ID of the ExpressRoute Gateway"
  value       = var.connectivity_config.expressroute_gateway != null ? try(module.alz_connectivity.virtual_network_gateways["prod-hub"].express_route.id, null) : null
}

output "expressroute_gateway_name" {
  description = "The name of the ExpressRoute Gateway"
  value       = var.connectivity_config.expressroute_gateway != null ? "${var.connectivity_config.expressroute_gateway.name}-${var.environment}" : null
}

output "expressroute_gateway_enabled" {
  description = "Whether ExpressRoute Gateway is configured and deployed"
  value       = var.connectivity_config.expressroute_gateway != null
}

# Network Security Group Information (if available from ALZ module)
output "network_security_group_id" {
  description = "The ID of the hub network security group"
  value       = try(module.alz_connectivity.network_security_groups["prod-hub"], null)
}

# DNS Information
output "dns_server_ip_addresses" {
  description = "DNS server IP addresses for the hub virtual network"
  value       = module.alz_connectivity.dns_server_ip_addresses["prod-hub"]
}

# Private DNS Zone Information
output "private_dns_zone_ids" {
  description = "Resource IDs of the private DNS zones"
  value       = var.connectivity_config.private_dns.enabled ? module.alz_connectivity.private_dns_zone_resource_ids : {}
}

# Route Tables Information
output "route_tables_firewall" {
  description = "Route tables associated with the firewall"
  value       = module.alz_connectivity.route_tables_firewall
}

output "route_tables_user_subnets" {
  description = "Route tables associated with the user subnets"
  value       = module.alz_connectivity.route_tables_user_subnets
}

# DDoS Protection Plan Information
output "ddos_protection_plan" {
  description = "DDoS protection plan information"
  value = {
    enabled = var.connectivity_config.ddos_protection.enabled
    name    = var.connectivity_config.ddos_protection.enabled ? "ddos-protection-${var.environment}" : null
    id      = var.connectivity_config.ddos_protection.enabled ? try(module.alz_connectivity.ddos_protection_plan_id, null) : null
  }
}

# NAT Gateway Information
output "nat_gateway_id" {
  description = "The ID of the NAT Gateway"
  value       = var.connectivity_config.nat_gateway != null && var.connectivity_config.nat_gateway.enabled ? try(module.nat_gateway[0].resource_id, null) : null
}

output "nat_gateway_name" {
  description = "The name of the NAT Gateway"
  value       = var.connectivity_config.nat_gateway != null && var.connectivity_config.nat_gateway.enabled ? try(module.nat_gateway[0].resource.name, null) : null
}


output "nat_gateway_public_ips" {
  description = "The public IP resources of the NAT Gateway"
  value       = var.connectivity_config.nat_gateway != null && var.connectivity_config.nat_gateway.enabled ? try(module.nat_gateway[0].public_ip_resource, {}) : {}
}

output "nat_gateway_enabled" {
  description = "Whether NAT Gateway is enabled"
  value       = var.connectivity_config.nat_gateway != null ? var.connectivity_config.nat_gateway.enabled : false
}
