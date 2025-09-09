# Connectivity Module - Naming Convention
# This file defines the naming standards for all connectivity resources

locals {
  # Core naming components
  env_prefix = lower(var.environment)

  # Azure Region Abbreviation Mapping
  region_abbreviations = {
    "Australia Central"    = "ac"
    "Australia Central 2"  = "ac2"
    "Australia East"       = "ae"
    "Australia Southeast"  = "ase"
    "Brazil South"         = "bs"
    "Canada Central"       = "cc"
    "Canada East"          = "ce"
    "Central India"        = "ci"
    "Central US"           = "cus"
    "East Asia"            = "ea"
    "East US"              = "eus"
    "East US 2"            = "eus2"
    "France Central"       = "fc"
    "France South"         = "fs"
    "Germany North"        = "gn"
    "Germany West Central" = "gwc"
    "Japan East"           = "je"
    "Japan West"           = "jw"
    "Korea Central"        = "kc"
    "Korea South"          = "ks"
    "North Central US"     = "ncus"
    "North Europe"         = "ne"
    "Norway East"          = "noe"
    "Norway West"          = "now"
    "South Africa North"   = "san"
    "South Africa West"    = "saw"
    "South Central US"     = "scus"
    "South India"          = "si"
    "Southeast Asia"       = "sea"
    "Sweden Central"       = "sc"
    "Sweden South"         = "ss"
    "Switzerland North"    = "sn"
    "Switzerland West"     = "sw"
    "UAE Central"          = "uc"
    "UAE North"            = "un"
    "UK South"             = "uks"
    "UK West"              = "ukw"
    "West Central US"      = "wcus"
    "West Europe"          = "we"
    "West India"           = "wi"
    "West US"              = "wus"
    "West US 2"            = "wus2"
    "West US 3"            = "wus3"
  }

  # Standardized location abbreviation using proper mapping
  location_abbr = lookup(local.region_abbreviations, var.location,
    substr(lower(replace(var.location, " ", "")), 0, 3)
  )

  # Random suffix for unique resources
  random_suffix = random_string.connectivity_naming.result

  # Service identifier for connectivity resources
  service     = "hub"
  hub_service = "hub"

  # Resource naming patterns for connectivity module
  connectivity_names = {
    # Resource Group
    resource_group = "rg-${local.env_prefix}-network-${local.location_abbr}-hub"

    # Virtual Network (Hub)
    virtual_network = "vnet-${local.env_prefix}-${local.hub_service}-${local.location_abbr}"

    # Subnets
    gateway_subnet  = "GatewaySubnet"       # Required name for Azure
    firewall_subnet = "AzureFirewallSubnet" # Required name for Azure
    bastion_subnet  = "AzureBastionSubnet"  # Required name for Azure

    # Network Security Groups
    default_nsg = "nsg-${local.env_prefix}-${local.service}-${local.location_abbr}-default"

    # Firewall
    firewall        = "fw-${local.env_prefix}-${local.hub_service}-${local.location_abbr}"
    firewall_policy = "fwpol-${local.env_prefix}-${local.hub_service}-${local.location_abbr}"

    # Gateways
    vpn_gateway = "vpngw-${local.env_prefix}-${local.hub_service}-${local.location_abbr}"
    er_gateway  = "ergw-${local.env_prefix}-${local.hub_service}-${local.location_abbr}"
    nat_gateway = "natgw-${local.env_prefix}-${local.hub_service}-${local.location_abbr}"

    # Bastion Host
    bastion_host = "bas-${local.env_prefix}-${local.hub_service}-${local.location_abbr}"

    # Public IPs
    firewall_pip    = "pip-fw-${local.env_prefix}-${local.hub_service}-${local.location_abbr}"
    vpn_pip         = "pip-vpngw-${local.env_prefix}-${local.hub_service}-${local.location_abbr}"
    bastion_pip     = "pip-bas-${local.env_prefix}-${local.hub_service}-${local.location_abbr}"
    nat_gateway_pip = "pip-natgw-${local.env_prefix}-${local.hub_service}-${local.location_abbr}"

    # Route Tables
    default_route_table  = "rt-${local.env_prefix}-${local.service}-${local.location_abbr}-default"
    firewall_route_table = "rt-${local.env_prefix}-${local.service}-${local.location_abbr}-fw"

    # Private DNS Zones (examples)
    blob_dns_zone  = "privatelink.blob.core.windows.net"
    vault_dns_zone = "privatelink.vaultcore.azure.net"

    # DDoS Protection Plan
    ddos_plan = "ddos-${local.env_prefix}-${local.hub_service}-${local.location_abbr}"

    # Network Watcher
    network_watcher = "nw-${local.env_prefix}-${local.service}-${local.location_abbr}"
  }

  # Standard tags for connectivity resources
  connectivity_tags = merge(var.default_tags, {
    Workload = "Connectivity"
  })
}

# Random string for unique resource naming in connectivity
resource "random_string" "connectivity_naming" {
  length  = 4
  upper   = false
  special = false
}
