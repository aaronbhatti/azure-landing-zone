# Default Azure Firewall Rules
# These rules are based on production ARM template and provide essential connectivity

locals {
  # Default Application Rules - Essential Azure Services
  default_application_rules = [
    {
      name        = "Authentication to Microsoft Online Services"
      description = "Allow authentication to Microsoft Online Services"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["login.microsoftonline.com"]
    },
    {
      name        = "Azure Marketplace"
      description = "Allow Azure Marketplace access"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["catalogartifact.azureedge.net"]
    },
    {
      name        = "Azure Agent traffic"
      description = "Allow Azure monitoring agent traffic"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses = ["*"]
      destination_fqdns = [
        "*.prod.warm.ingest.monitor.core.windows.net",
        "gcs.prod.monitoring.core.windows.net"
      ]
    },
    {
      name        = "Agent and side-by-side (SXS) stack updates"
      description = "Allow AVD agent and SXS stack updates"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["mrsglobalsteus2prod.blob.core.windows.net"]
    },
    {
      name        = "Azure portal support"
      description = "Allow Azure portal support for AVD"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["wvdportalstorageblob.blob.core.windows.net"]
    },
    {
      name        = "Azure Instance Metadata service endpoint"
      description = "Allow access to Azure Instance Metadata Service"
      protocols = [
        {
          type = "Http"
          port = 80
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["169.254.169.254"]
    },
    {
      name        = "Session host health monitoring"
      description = "Allow session host health monitoring"
      protocols = [
        {
          type = "Http"
          port = 80
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["168.63.129.16"]
    },
    {
      name        = "Azure Certificates"
      description = "Allow certificate revocation and validation"
      protocols = [
        {
          type = "Http"
          port = 80
        }
      ]
      source_addresses = ["*"]
      destination_fqdns = [
        "oneocsp.microsoft.com",
        "www.microsoft.com",
        "ctldl.windowsupdate.com"
      ]
    },
    {
      name        = "Microsoft URL shortener"
      description = "Allow Microsoft URL shortener access"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["aka.ms"]
    },
    {
      name        = "Azure Telemetry Service"
      description = "Allow Azure telemetry service"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["*.events.data.microsoft.com"]
    },
    {
      name        = "Internet connectivity test"
      description = "Detects if the session host is connected to the internet"
      protocols = [
        {
          type = "Http"
          port = 80
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["www.msftconnecttest.com"]
    },
    {
      name        = "Windows Update"
      description = "Allow Windows Update traffic"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["*.prod.do.dsp.mp.microsoft.com"]
    },
    {
      name        = "OneDrive client updates"
      description = "Updates for OneDrive client software"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["*.sfx.ms"]
    },
    {
      name        = "Certificate revocation check"
      description = "Certificate revocation check"
      protocols = [
        {
          type = "Http"
          port = 80
        }
      ]
      source_addresses = ["*"]
      destination_fqdns = [
        "*.digicert.com",
        "cacerts.digicert.com",
        "cacerts.digicert.cn",
        "cacerts.geotrust.com",
        "www.microsoft.com",
        "crl3.digicert.com",
        "crl4.digicert.com",
        "crl.digicert.cn",
        "cdp.geotrust.com",
        "ocsp.digicert.com",
        "ocsp.digicert.cn",
        "oneocsp.microsoft.com",
        "status.geotrust.com"
      ]
    },
    {
      name        = "Azure DNS resolution"
      description = "Allow Azure DNS resolution"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses = ["*"]
      destination_fqdns = [
        "*.azure-dns.com",
        "*.azure-dns.net"
      ]
    },
    {
      name        = "Azure Diagnostic settings"
      description = "Allow Azure diagnostic settings"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["*eh.servicebus.windows.net"]
    },
    {
      name        = "Azure Troubleshooting data"
      description = "Allow Azure troubleshooting data"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["*.servicebus.windows.net"]
    },
    {
      name        = "Microsoft FWLinks"
      description = "Allow Microsoft forward links"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["go.microsoft.com"]
    },
    {
      name        = "Microsoft Documentation"
      description = "Allow Microsoft documentation access"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses = ["*"]
      destination_fqdns = [
        "learn.microsoft.com",
        "privacy.microsoft.com"
      ]
    },
    {
      name        = "Office updates"
      description = "Automatic updates for Microsoft Office"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["*.cdn.office.net"]
    },
    {
      name        = "Microsoft Graph API"
      description = "Microsoft Graph API service traffic"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["graph.microsoft.com"]
    },
    {
      name        = "AVD Service traffic"
      description = "Azure Virtual Desktop service traffic"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["windows365.microsoft.com"]
    },
    {
      name        = "Microsoft Connection center"
      description = "Microsoft Connection center"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses  = ["*"]
      destination_fqdns = ["ecs.office.com"]
    },
    {
      name        = "Microsoft Entra hybrid join"
      description = "Microsoft Entra (Azure AD) hybrid join"
      protocols = [
        {
          type = "Http"
          port = 80
        },
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses = ["*"]
      destination_fqdns = [
        "enterpriseregistration.windows.net",
        "login.microsoftonline.com",
        "device.login.microsoftonline.com",
        "autologon.microsoftazuread-sso.com"
      ]
    },
    {
      name        = "Basic web browsing"
      description = "Allow essential web browsing for Windows services"
      protocols = [
        {
          type = "Http"
          port = 80
        },
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses = ["*"]
      destination_fqdns = [
        "*.windowsupdate.com",
        "*.update.microsoft.com",
        "*.windows.com",
        "*.microsoft.com",
        "*.do.dsp.mp.microsoft.com",
        "*.delivery.mp.microsoft.com",
        "*.dl.delivery.mp.microsoft.com",
        "*.msftconnecttest.com",
        "*.msftncsi.com"
      ]
    },
    {
      name        = "Web Categories"
      description = "Allow approved web categories"
      protocols = [
        {
          type = "Http"
          port = 80
        },
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses = ["*"]
      web_categories = [
        "alcoholandtobacco",
        "gambling",
        "imagesharing",
        "streamingmediaanddownloads",
        "entertainment",
        "business",
        "computersandtechnology",
        "education",
        "finance",
        "forumsandnewsgroups",
        "government",
        "healthandmedicine",
        "informationsecurity",
        "jobsearch",
        "news",
        "nonprofitsandngos",
        "personalsites",
        "professionalnetworking",
        "searchenginesandportals",
        "translators",
        "webrepositoryandstorage",
        "webbasedemail",
        "shopping",
        "socialnetworking",
        "arts",
        "fashionandbeauty",
        "general",
        "leisureandrecreation",
        "natureandconservation",
        "politicsandlaw",
        "realestate",
        "religion",
        "restaurantsanddining",
        "sports",
        "transportation",
        "travel"
      ]
    },
    {
      name        = "AVD Low Utilization Rules"
      description = "Allow AVD service traffic (low priority)"
      protocols = [
        {
          type = "Https"
          port = 443
        }
      ]
      source_addresses = ["*"]
      destination_fqdns = [
        "*.wvd.microsoft.com",
        "windows.cloud.microsoft"
      ]
    },

  ]

  # Default Network Rules - Essential connectivity
  default_network_rules = [
    {
      name                  = "DNS"
      description           = "Allow DNS queries"
      protocols             = ["UDP", "TCP"]
      source_addresses      = ["*"]
      destination_addresses = var.external_service_ips.dns_servers
      destination_ports     = ["53"]
    },
    {
      name                  = "Enable ICMP"
      description           = "Allow ICMP (ping) traffic"
      protocols             = ["ICMP"]
      source_addresses      = ["*"]
      destination_addresses = ["*"]
      destination_ports     = ["*"]
    },
    {
      name                  = "AVD Service Traffic"
      description           = "Allow AVD service traffic"
      protocols             = ["TCP"]
      source_addresses      = ["*"]
      destination_addresses = ["AzureCloud"]
      destination_ports     = ["443"]
    },
    {
      name                  = "Azure Monitor Agent"
      description           = "Allow Azure Monitor agent traffic"
      protocols             = ["TCP"]
      source_addresses      = ["*"]
      destination_addresses = ["AzureMonitor"]
      destination_ports     = ["443"]
    },
    {
      name                  = "Azure Marketplace Network"
      description           = "Allow Azure Marketplace network access"
      protocols             = ["TCP"]
      source_addresses      = ["*"]
      destination_addresses = ["AzureFrontDoor.Frontend"]
      destination_ports     = ["443"]
    },
    {
      name                  = "STUN/TURN Relay"
      description           = "Allow STUN/TURN relay for Teams/AVD"
      protocols             = ["UDP"]
      source_addresses      = ["*"]
      destination_addresses = [var.external_service_ips.stun_turn_main]
      destination_ports     = ["3478"]
    },
    {
      name                  = "STUN/TURN Relay Legacy"
      description           = "Allow STUN/TURN relay legacy range"
      protocols             = ["UDP"]
      source_addresses      = ["*"]
      destination_addresses = [var.external_service_ips.stun_turn_legacy]
      destination_ports     = ["3478"]
    },
    {
      name                  = "NTP"
      description           = "Allow NTP time synchronization"
      protocols             = ["UDP"]
      source_addresses      = ["*"]
      destination_addresses = ["*"]
      destination_ports     = ["123"]
    },
    {
      name                  = "FTP"
      description           = "Allow FTP traffic from spoke networks"
      protocols             = ["TCP"]
      source_addresses      = var.all_spoke_address_spaces
      destination_addresses = ["*"]
      destination_ports     = ["20", "21"]
    },
    {
      name                  = "Telnet"
      description           = "Allow Telnet traffic from spoke networks"
      protocols             = ["TCP"]
      source_addresses      = var.all_spoke_address_spaces
      destination_addresses = ["*"]
      destination_ports     = ["23"]
    },
    {
      name                  = "SMTP"
      description           = "Allow SMTP traffic from spoke networks"
      protocols             = ["TCP"]
      source_addresses      = var.all_spoke_address_spaces
      destination_addresses = ["*"]
      destination_ports     = ["25"]
    },
    {
      name                  = "NNTP"
      description           = "Allow NNTP traffic from spoke networks"
      protocols             = ["TCP"]
      source_addresses      = var.all_spoke_address_spaces
      destination_addresses = ["*"]
      destination_ports     = ["119"]
    },
    {
      name        = "LDAP/LDAPS"
      description = "Allow LDAP and LDAPS traffic to domain controllers"
      protocols   = ["TCP", "UDP"]
      source_addresses = concat(
        var.specific_subnet_ranges.domain_subnets,
        var.specific_subnet_ranges.avd_session_hosts
      )
      destination_addresses = var.domain_controller_ips
      destination_ports     = ["389", "636"]
    },
    {
      name        = "MS-RPC"
      description = "Allow Microsoft RPC endpoint mapper"
      protocols   = ["TCP"]
      source_addresses = concat(
        var.specific_subnet_ranges.domain_subnets,
        var.specific_subnet_ranges.avd_session_hosts
      )
      destination_addresses = concat(
        var.domain_controller_ips,
        ["10.20.17.8"]
      )
      destination_ports = ["135"]
    },
    {
      name        = "SMB"
      description = "Allow SMB file sharing"
      protocols   = ["TCP"]
      source_addresses = concat(
        var.specific_subnet_ranges.domain_subnets,
        var.specific_subnet_ranges.avd_session_hosts
      )
      destination_addresses = concat(
        var.specific_subnet_ranges.domain_subnets,
        var.specific_subnet_ranges.infrastructure_subnets,
        var.external_service_ips.external_services
      )
      destination_ports = ["135", "445"]
    },
    {
      name        = "Kerberos"
      description = "Allow Kerberos authentication"
      protocols   = ["TCP", "UDP"]
      source_addresses = concat(
        var.specific_subnet_ranges.domain_subnets,
        var.specific_subnet_ranges.avd_session_hosts
      )
      destination_addresses = var.domain_controller_ips
      destination_ports     = ["88", "464"]
    },
    {
      name        = "RPC Dynamic Port Range"
      description = "Allow RPC dynamic port range"
      protocols   = ["TCP"]
      source_addresses = concat(
        var.specific_subnet_ranges.domain_subnets,
        var.specific_subnet_ranges.avd_session_hosts,
        var.specific_subnet_ranges.infrastructure_subnets,
        var.external_service_ips.external_services
      )
      destination_addresses = concat(
        var.specific_subnet_ranges.domain_subnets,
        var.specific_subnet_ranges.avd_session_hosts,
        var.specific_subnet_ranges.infrastructure_subnets,
        var.external_service_ips.external_services
      )
      destination_ports = ["49152-65535"]
    },
    {
      name                  = "Global Catalog"
      description           = "Allow Active Directory Global Catalog"
      protocols             = ["TCP"]
      source_addresses      = ["*"]
      destination_addresses = var.domain_controller_ips
      destination_ports     = ["3268", "3269"]
    },
    {
      name        = "WinRM"
      description = "Allow Windows Remote Management"
      protocols   = ["TCP", "UDP"]
      source_addresses = concat(
        var.specific_subnet_ranges.domain_subnets,
        var.specific_subnet_ranges.avd_session_hosts
      )
      destination_addresses = concat(
        var.specific_subnet_ranges.domain_subnets,
        var.specific_subnet_ranges.avd_session_hosts
      )
      destination_ports = ["5985", "5986"]
    },
    {
      name             = "RDP"
      description      = "Allow Remote Desktop Protocol from Bastion"
      protocols        = ["TCP", "UDP"]
      source_addresses = [var.specific_subnet_ranges.bastion_subnet]
      destination_addresses = concat(
        var.specific_subnet_ranges.domain_subnets,
        var.specific_subnet_ranges.infrastructure_subnets,
        var.specific_subnet_ranges.avd_session_hosts
      )
      destination_ports = ["3389"]
    },
    {
      name                  = "Active Directory Web Services"
      description           = "Allow Active Directory Web Services"
      protocols             = ["TCP"]
      source_addresses      = ["*"]
      destination_addresses = var.domain_controller_ips
      destination_ports     = ["9389"]
    }
  ]

  # Default Application Rule Collection
  default_application_rule_collection = {
    name     = "DefaultApplicationRules"
    priority = 300
    action   = "Allow"
    rules    = local.default_application_rules
  }

  # Default Network Rule Collection
  # default_network_rule_collection removed - merged with essential rules

  # Merge user-defined rules with defaults
  merged_application_rules = concat(
    [local.default_application_rule_collection],
    coalesce(try(var.connectivity_config.firewall.policy.application_rule_collections, null), [])
  )

  # Essential Network Rules for spoke-to-spoke connectivity (renamed to avoid duplicates)
  essential_network_rules = [
    {
      name                  = "Spoke LDAP/LDAPS"
      description           = "Allow LDAP and LDAPS traffic to domain controllers"
      protocols             = ["TCP", "UDP"]
      source_addresses      = var.all_spoke_address_spaces
      destination_addresses = var.identity_spoke_address_space
      destination_ports     = ["389", "636"]
    },
    {
      name             = "Spoke MS-RPC"
      description      = "Allow Microsoft RPC endpoint mapper"
      protocols        = ["TCP"]
      source_addresses = var.all_spoke_address_spaces
      destination_addresses = concat(
        var.identity_spoke_address_space,
        var.infrastructure_spoke_address_space
      )
      destination_ports = ["135"]
    },
    {
      name             = "Spoke SMB"
      description      = "Allow SMB file sharing between spokes"
      protocols        = ["TCP"]
      source_addresses = var.all_spoke_address_spaces
      destination_addresses = concat(
        var.identity_spoke_address_space,
        var.infrastructure_spoke_address_space,
        var.avd_spoke_address_space
      )
      destination_ports = ["135", "445"]
    },
    {
      name                  = "Spoke Kerberos"
      description           = "Allow Kerberos authentication to domain controllers"
      protocols             = ["TCP", "UDP"]
      source_addresses      = var.all_spoke_address_spaces
      destination_addresses = var.identity_spoke_address_space
      destination_ports     = ["88", "464"]
    },
    {
      name                  = "Spoke RPC Dynamic Port Range"
      description           = "Allow RPC dynamic port range between spokes"
      protocols             = ["TCP"]
      source_addresses      = var.all_spoke_address_spaces
      destination_addresses = var.all_spoke_address_spaces
      destination_ports     = ["49152-65535"]
    },
    {
      name                  = "Spoke Global Catalog"
      description           = "Allow Active Directory Global Catalog"
      protocols             = ["TCP"]
      source_addresses      = ["*"]
      destination_addresses = var.identity_spoke_address_space
      destination_ports     = ["3268", "3269"]
    },
    {
      name             = "Spoke WinRM"
      description      = "Allow Windows Remote Management between spokes"
      protocols        = ["TCP", "UDP"]
      source_addresses = var.all_spoke_address_spaces
      destination_addresses = concat(
        var.identity_spoke_address_space,
        var.infrastructure_spoke_address_space,
        var.avd_spoke_address_space
      )
      destination_ports = ["5985", "5986"]
    },
    {
      name             = "Spoke RDP"
      description      = "Allow Remote Desktop Protocol from Bastion"
      protocols        = ["TCP", "UDP"]
      source_addresses = var.hub_address_space
      destination_addresses = concat(
        var.identity_spoke_address_space,
        var.infrastructure_spoke_address_space,
        var.avd_spoke_address_space
      )
      destination_ports = ["3389"]
    },
    {
      name                  = "Spoke SQL Server"
      description           = "Allow SQL Server traffic to infrastructure spoke"
      protocols             = ["TCP", "UDP"]
      source_addresses      = var.all_spoke_address_spaces
      destination_addresses = var.infrastructure_spoke_address_space
      destination_ports     = ["1433", "1434"]
    },
    {
      name                  = "Spoke AD Web Services"
      description           = "Allow Active Directory Web Services"
      protocols             = ["TCP"]
      source_addresses      = ["*"]
      destination_addresses = var.identity_spoke_address_space
      destination_ports     = ["9389"]
    }
  ]

  # Combined Network Rule Collection - merging essential and default rules with unique names
  combined_network_rule_collection = {
    name     = "DefaultNetworkRules"
    priority = 200
    action   = "Allow"
    rules    = concat(local.essential_network_rules, local.default_network_rules)
  }

  # Use combined network rules
  merged_network_rules = concat(
    [local.combined_network_rule_collection],
    coalesce(try(var.connectivity_config.firewall.policy.network_rule_collections, null), [])
  )
}