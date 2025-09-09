# Azure Landing Zone Configuration Template

Copy this file to environments/my-deployment.tfvars and customize with your values
This template provides a complete example configuration with all available options

## Basic Configuration - REQUIRED

```hcl
org_name    = "CONTOSO"      # Your organization name (3-64 chars, alphanumeric, hyphens, underscores)
environment = "prod"         # Environment: dev, staging, or prod
location    = "UK South"     # Azure region for resource deployment (see supported regions below)
```

## Supported Azure Regions

The landing zone uses standardized region abbreviations for resource naming. All Azure regions are supported with the following mappings:

| Region Name | Abbreviation | Region Name | Abbreviation |
|-------------|--------------|-------------|--------------|
| Australia Central | ac | Norway East | noe |
| Australia Central 2 | ac2 | Norway West | now |
| Australia East | ae | South Africa North | san |
| Australia Southeast | ase | South Africa West | saw |
| Brazil South | bs | South Central US | scus |
| Canada Central | cc | South India | si |
| Canada East | ce | Southeast Asia | sea |
| Central India | ci | Sweden Central | sc |
| Central US | cus | Sweden South | ss |
| East Asia | ea | Switzerland North | sn |
| East US | eus | Switzerland West | sw |
| East US 2 | eus2 | UAE Central | uc |
| France Central | fc | UAE North | un |
| France South | fs | UK South | uks |
| Germany North | gn | UK West | ukw |
| Germany West Central | gwc | West Central US | wcus |
| Japan East | je | West Europe | we |
| Japan West | jw | West India | wi |
| Korea Central | kc | West US | wus |
| Korea South | ks | West US 2 | wus2 |
| North Central US | ncus | West US 3 | wus3 |
| North Europe | ne | | |

Examples:

- `location = "UK South"` → resources named with `uks`
- `location = "East US 2"` → resources named with `eus2`
- `location = "North Europe"` → resources named with `ne`

### Resource Naming Best Practices

**Use computed naming**: The modules automatically generate resource names based on your `location` setting. Avoid hardcoding resource names unless you need to override the standard.

```hcl
# ✅ GOOD - Uses computed naming (recommended)
connectivity_config = {
  enabled = true
  # resource_group_name = "rg-prod-network-uks-hub" # Override computed naming if needed
}

# ❌ AVOID - Hardcoded names (use only when you need to override)
connectivity_config = {
  enabled = true
  resource_group_name = "rg-custom-network-hub"  # Only if you need custom naming
}
```

## Subscription Configuration - REQUIRED

You can use the same subscription ID for all if deploying to a single subscription

```hcl
management_subscription_id   = "12345678-1234-1234-1234-123456789012"  # Management resources
connectivity_subscription_id = "12345678-1234-1234-1234-123456789012"  # Hub networking
identity_subscription_id     = "12345678-1234-1234-1234-123456789012"  # Domain controllers (optional)
infra_subscription_id        = "12345678-1234-1234-1234-123456789012"  # Infrastructure workloads (optional)
avd_subscription_id          = "12345678-1234-1234-1234-123456789012"  # Azure Virtual Desktop (optional)
aib_subscription_id          = "12345678-1234-1234-1234-123456789012"  # Azure Image Builder (optional)
```

## Resource Tags - Apply to all resources

```hcl
default_tags = {
  Environment = "Production"
  Owner       = "IT"
  CostCenter  = "Shared"
}
```

## CORE GOVERNANCE CONFIGURATION (ALZ Management Groups & Policies)

```hcl
core_config = {
  enabled                       = true
  management_group_display_name = "CNNECT"               # Root management group name  
  management_group_id           = "alz"                  # Management group ID (auto-generated if null)
  management_group_parent_id    = null                   # Use tenant root (recommended)
  enable_policy_assignments     = true                   # Deploy ALZ policies
  security_contact_email        = null                   # For security alerts (optional - not yet supported in current ALZ version)
  
  # Policy default values - automatically populated by management module integration
  # Manual policy parameter configuration is NO LONGER REQUIRED
  policy_default_values = {
    # Azure Monitor Agent (AMA) integration values are automatically configured:
    # - log_analytics_workspace_id: Auto-populated from management module
    # - ama_change_tracking_data_collection_rule_id: Auto-configured
    # - ama_vm_insights_data_collection_rule_id: Auto-configured  
    # - ama_mdfc_sql_data_collection_rule_id: Auto-configured
    # - ama_user_assigned_managed_identity_id: Auto-configured
    # - automation_account_id: Auto-configured when automation account is enabled
    #
    # Add custom policy overrides here only if needed
  }
}
```

## MANAGEMENT LAYER CONFIGURATION (Monitoring & Automation)

```hcl
management_config = {
  enabled = true
  
  # Log Analytics Workspace Configuration
  log_analytics = {
    retention_in_days = 30         # Log retention (30-730 days)
    sku               = "PerGB2018" # Pricing tier
  }

  # Automation Account Configuration
  automation_account = {
    sku = "Basic"  # Basic or Free tier
  }
}
```

### 🔄 Azure Monitor Agent (AMA) Integration

The management layer automatically provisions **Azure Monitor Agent (AMA)** components that integrate with ALZ policies:

**✅ Automatic Components Created:**

- **Log Analytics Workspace**: Central logging and monitoring
- **Data Collection Rules (DCRs)**:
  - `dcr-vm-insights`: VM performance and dependency monitoring
  - `dcr-change-tracking`: Configuration and file change tracking  
  - `dcr-defender-sql`: Microsoft Defender for SQL monitoring
- **User-Assigned Managed Identity**: `uami-ama` for secure agent authentication
- **Log Analytics Solutions**: VM Insights, Container Insights, Microsoft Sentinel

**✅ Policy Integration Benefits:**

- **Zero Manual Configuration**: Policy parameters auto-populated from management resources
- **Automatic VM Monitoring**: All VMs get monitoring agents via policy enforcement
- **Centralized Logging**: All diagnostic data flows to the Log Analytics workspace
- **Security Monitoring**: Defender for Cloud integration with AMA data collection
- **Change Tracking**: File and configuration monitoring across all resources

**🎯 No Action Required:** AMA integration works automatically when both `management_config.enabled = true` and `core_config.enabled = true`

## HUB NETWORKING CONFIGURATION (Connectivity Layer)

```hcl
connectivity_config = {
  enabled             = true
  # resource_group_name = "rg-prod-network-uks-hub" # Override computed naming if needed
  
  # Hub Virtual Network - Central connectivity hub
  hub_virtual_network = {
    address_space = ["10.0.0.0/16"]  # Hub network address space

    subnets = {
      # Required Azure subnets
      "AzureBastionSubnet" = {
        address_prefixes = ["10.0.1.0/24"]  # Bastion subnet (required name)
      }
      "GatewaySubnet" = {
        address_prefixes = ["10.0.2.0/24"]  # VPN/ER Gateway subnet (required name)
      }
      "AzureFirewallSubnet" = {
        address_prefixes = ["10.0.3.0/24"]  # Firewall subnet (required name)
      }
      
      # Optional custom subnets
      # "snet-shared-services" = {
      #   address_prefixes = ["10.0.4.0/24"]
      #   service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
      # }
    }
  }

  # Azure Firewall Configuration
  firewall = {
    sku_name = "AZFW_VNet"  # AZFW_VNet (Standard/Premium) or AZFW_Hub
    sku_tier = "Standard"   # Standard or Premium (Premium has IDPS, TLS inspection)
    
    policy = {
      # name                     = "fwpol-prod-hub-uks" # Override computed naming if needed
      threat_intelligence_mode = "Alert"  # Off, Alert, Deny
      
      # DNS Configuration
      dns_settings = {
        servers      = ["168.63.129.16"]  # Azure DNS (change to DC IPs when using domain controllers)
        enable_proxy = true               # Enable DNS proxy for spoke networks
      }
      
      # Custom rule collections (merged with defaults)
      # application_rule_collections = []  # Add custom application rules here
      # network_rule_collections = []     # Add custom network rules here
    }
  }

  # VPN Gateway Configuration (for hybrid connectivity)
  vpn_gateway = {
    enabled               = false         # Enable for on-premises connectivity
    type                  = "Vpn"        # Vpn or ExpressRoute
    sku                   = "VpnGw1AZ"   # VpnGw1AZ, VpnGw2AZ, VpnGw3AZ (AZ = zone-redundant)
    zones                 = ["1", "2", "3"]
    enable_active_active  = true         # Dual gateway IPs for redundancy
  }

  # ExpressRoute Gateway Configuration
  expressroute_gateway = {
    enabled = false  # Enable for ExpressRoute connectivity
  }

  # Private DNS Configuration
  private_dns = {
    enabled = false  # Enable to create private DNS zones
    zones   = []     # List of private DNS zones to create
  }

  # Azure Bastion Configuration (secure RDP/SSH access)
  bastion = {
    enabled               = true            # Enable/disable bastion deployment
    subnet_address_prefix = "10.0.1.0/24"  # Must match AzureBastionSubnet above
    sku                   = "Basic"         # Basic or Standard
    zones                 = []              # Basic SKU doesn't support zones
  }

  # NAT Gateway Configuration (for outbound internet access)
  nat_gateway = {
    enabled = true    # Recommended to prevent SNAT port exhaustion
    zones   = ["1"]   # Single zone for cost optimization
    public_ips = {
      count = 1       # Number of public IPs (more IPs = more SNAT ports)
      sku   = "Standard"
    }
  }

  # DDoS Protection (expensive - usually disabled for cost)
  ddos_protection = {
    enabled = false
  }
}
```

## IDENTITY SERVICES CONFIGURATION (Domain Controllers)

```hcl
identity_config = {
  enabled             = true                           # Enable identity spoke
  # resource_group_name = "rg-prod-identity-uks-network" # Override computed naming if needed

  # Identity Spoke Network
  virtual_network = {
    # name          = "vnet-prod-identity-uks" # Override computed naming if needed
    address_space = ["10.1.0.0/16"]  # Identity network address space

    subnets = {
      "snet-identity" = {
        address_prefixes = ["10.1.1.0/24"]  # Domain controllers subnet
      }
    }
  }

  # Virtual Machines Configuration (Domain Controllers)
  deploy_virtual_machines = true
  virtual_machines = {
    "dc" = {
      count              = 2                    # Number of domain controllers (2+ for HA)
      vm_size            = "Standard_D2s_v5"   # VM size (D2s_v5 minimum for DCs)
      os_type            = "Windows"
      os_sku             = "2022-datacenter-g2"
      admin_username     = "dcadmin"
      os_disk_size_gb    = 128
      subnet_name        = "snet-identity"
      vm_name_prefix     = "DC"               # Results in DC01, DC02, etc.
      availability_zones = ["1", "2"]         # Deploy across zones for HA
      static_ip_start    = "10.1.1.10"       # First DC gets .10, second gets .11
      enable_extensions  = true               # Install monitoring agents

      # Network Interface Configuration
      network_interfaces = [
        {
          subnet_name                   = "snet-identity"
          private_ip_allocation_method  = "Static"
          static_ip_address            = "10.1.1.10"  # Overridden by static_ip_start logic
          enable_ip_forwarding          = false
          enable_accelerated_networking = false       # Not supported on all DC VM sizes
        }
      ]

      # Additional data disks for AD database/logs (optional)
      # data_disks = [
      #   {
      #     size_gb              = 256
      #     caching              = "None"           # Critical for AD DS
      #     storage_account_type = "Premium_LRS"
      #     lun                  = 0
      #   }
      # ]
    }
  }

  # Backup Configuration
  enable_backup = true
  backup_config = {
    sku                           = "Standard"
    storage_mode_type             = "LocallyRedundant"  # LRS for cost optimization
    cross_region_restore_enabled  = false               # GRS backup (more expensive)
    public_network_access_enabled = true
    immutability                  = "Unlocked"          # Locked for compliance (optional)
    
    # Backup Policy Configuration (optional)
    backup_policy = {
      name            = "DomainControllerBackupPolicy"
      policy_type     = "V2"
      timezone        = "UTC"
      frequency       = "Daily"
      backup_time     = "22:00"
      retention_daily = 35
    }
  }

  # Connect to hub network
  connect_to_hub = true

  # Key Vault for storing credentials (optional)
  enable_key_vault = false
  key_vault_config = null
}
```

## INFRASTRUCTURE WORKLOADS CONFIGURATION (Application Tier)

```hcl
infra_config = {
  enabled             = true
  # resource_group_name = "rg-prod-infra-uks-network" # Override computed naming if needed

  # Infrastructure Spoke Network
  virtual_network = {
    # name          = "vnet-prod-infra-uks" # Override computed naming if needed
    address_space = ["10.2.0.0/16"]  # Infrastructure network address space

    subnets = {
      "snet-web" = {
        address_prefixes = ["10.2.1.0/24"]  # Web tier
      }
      "snet-app" = {
        address_prefixes = ["10.2.2.0/24"]  # Application tier
      }
      "snet-data" = {
        address_prefixes = ["10.2.3.0/24"]  # Database tier
      }
    }
  }

  # Connect to hub for internet access
  connect_to_hub = true
  enable_backup  = true
  enable_storage = false  # Disable if storage policies conflict

  # Backup Configuration
  backup_config = {
    sku                           = "Standard"
    storage_mode_type             = "LocallyRedundant"
    cross_region_restore_enabled  = false
    public_network_access_enabled = true
    immutability                  = "Unlocked"
    
    # Backup Policy Configuration (optional)
    backup_policy = {
      name            = "InfrastructureBackupPolicy"
      policy_type     = "V2"
      timezone        = "UTC"
      frequency       = "Daily"
      backup_time     = "22:00"
      retention_daily = 35
    }
  }

  # Virtual Machines Configuration (Multi-tier application)
  deploy_virtual_machines = true
  virtual_machines = {
    # Web Server Tier
    "web" = {
      count              = 2
      vm_size            = "Standard_D2s_v5"
      os_type            = "Windows"
      os_sku             = "2022-datacenter-g2"
      admin_username     = "azureadmin"
      os_disk_size_gb    = 128
      subnet_name        = "snet-web"
      vm_name_prefix     = "WEB"
      availability_zones = ["1", "2"]
      static_ip_start    = "10.2.1.10"
      enable_extensions  = true

      network_interfaces = [
        {
          subnet_name                   = "snet-web"
          private_ip_allocation_method  = "Static"
          static_ip_address            = "10.2.1.10"  # Managed by static_ip_start
          enable_accelerated_networking = true        # Improves network performance
        }
      ]
    }

    # Application Server Tier  
    "app" = {
      count              = 2
      vm_size            = "Standard_D4s_v5"  # Larger size for app processing
      os_type            = "Windows"
      os_sku             = "2022-datacenter-g2"
      admin_username     = "azureadmin"
      os_disk_size_gb    = 128
      subnet_name        = "snet-app"
      vm_name_prefix     = "APP"
      availability_zones = ["1", "2"]
      static_ip_start    = "10.2.2.10"
      enable_extensions  = true

      network_interfaces = [
        {
          subnet_name                   = "snet-app"
          private_ip_allocation_method  = "Static"
          static_ip_address            = "10.2.2.10"
          enable_accelerated_networking = true
        }
      ]

      # Additional data disks for application data
      data_disks = [
        {
          size_gb              = 256
          storage_account_type = "Premium_LRS"
          caching              = "ReadWrite"
          lun                  = 0
        }
      ]
    }
  }
}
```

## AZURE VIRTUAL DESKTOP CONFIGURATION (AVD)

```hcl
avd_config = {
  enabled = true

  # Basic Configuration
  # resource_group_name                = "rg-prod-avd-uks" # Override computed naming if needed
  # workspace_name                     = "ws-prod-avd-uks" # Override computed naming if needed
  workspace_friendly_name            = "Production AVD Workspace"
  workspace_description              = "Production Azure Virtual Desktop workspace"
  public_network_access_enabled      = true

  # Host Pool Configuration
  host_pool = {
    # name                             = "hp-prod-avd-uks" # Override computed naming if needed
    friendly_name                    = "Production AVD Host Pool"
    description                      = "Production Azure Virtual Desktop Host Pool"
    type                             = "Pooled"                    # Pooled or Personal
    maximum_sessions_allowed         = 50                         # Max sessions per host
    load_balancer_type               = "BreadthFirst"             # BreadthFirst or DepthFirst
    custom_rdp_properties            = "drivestoredirect:s:;usbdevicestoredirect:s:*;redirectclipboard:i:1;redirectprinters:i:1;audiomode:i:0;videoplaybackmode:i:1;devicestoredirect:s:*;redirectcomports:i:0;redirectsmartcards:i:1;enablecredsspsupport:i:1;redirectwebauthn:i:1;use multimon:i:1;autoreconnection enabled:i:1;bandwidthautodetect:i:1;networkautodetect:i:1;audiocapturemode:i:1;encode redirected video capture:i:1;camerastoredirect:s:*;redirectlocation:i:1;keyboardhook:i:1;smart sizing:i:1;dynamic resolution:i:1;maximizetocurrentdisplays:i:1;singlemoninwindowedmode:i:1;screen mode id:i:2;enablerdsaadauth:i:1"
    start_vm_on_connect              = true                       # Power on VMs when users connect
    validate_environment             = false                      # Validation environment flag
  }

  # Application Group Configuration
  application_group = {
    # name                         = "ag-prod-avd-uks" # Override computed naming if needed
    friendly_name                = "Production AVD Desktop Application Group"
    description                  = "Production Azure Virtual Desktop Desktop Application Group"
    type                         = "Desktop"                      # Desktop or RemoteApp
    default_desktop_display_name = "Production Desktop"
  }

  # Enable AVD Insights for monitoring
  enable_insights = true

  # Enable RBAC role assignments for Start VM on Connect feature
  enable_start_vm_rbac = true

  # Network Configuration - dedicated AVD spoke
  create_virtual_network = true
  connect_to_hub         = true
  virtual_network = {
    # name          = "vnet-prod-avd-uks" # Override computed naming if needed
    address_space = ["10.3.0.0/16"]

    subnets = {
      "snet-prod-desktop-uks" = {
        address_prefixes  = ["10.3.1.0/24"]
        service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
      }
      "snet-prod-admin-desktop-uks" = {
        address_prefixes  = ["10.3.2.0/24"]
        service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
      }
      "snet-prod-thirdparty-desktop-uks" = {
        address_prefixes  = ["10.3.3.0/24"]
        service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
      }
      "snet-prod-test-desktop-uks" = {
        address_prefixes  = ["10.3.4.0/24"]
        service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
      }
      "snet-prod-build-desktop-uks" = {
        address_prefixes  = ["10.3.5.0/24"]
        service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
      }
    }
  }

  # FSLogix Configuration (user profiles)
  fslogix = {
    enabled                 = true
    profile_share_size_gb   = 100  # GB per share
    container_share_size_gb = 100
    enable_private_endpoint = false # More secure but complex
  }

  # Auto-scaling Configuration
  # Note: Scaling plan is always created but can be customized
  scaling_plan = {
    name      = "scaling-plan-prod-uks"  # Required field for scaling plan
    time_zone = "GMT Standard Time"
    
    schedules = {
      "Weekday" = {
        name                                 = "Weekday"
        days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        ramp_up_start_time                   = "07:00"
        ramp_up_load_balancing_algorithm     = "BreadthFirst"
        ramp_up_minimum_hosts_percent        = 40
        ramp_up_capacity_threshold_percent   = 80
        peak_start_time                      = "08:00"
        peak_load_balancing_algorithm        = "DepthFirst"
        ramp_down_start_time                 = "19:00"
        ramp_down_load_balancing_algorithm   = "DepthFirst"
        ramp_down_minimum_hosts_percent      = 5
        ramp_down_capacity_threshold_percent = 90
        ramp_down_force_logoff_users         = false
        ramp_down_wait_time_minutes          = 15
        ramp_down_notification_message       = "This desktop is shutting down in 15 minutes. Please save your work and logout."
        ramp_down_stop_hosts_when            = "ZeroActiveSessions"
        off_peak_start_time                  = "20:00"
        off_peak_load_balancing_algorithm    = "DepthFirst"
      }
      "Weekend" = {
        name                                 = "Weekend"
        days_of_week                         = ["Saturday", "Sunday"]
        ramp_up_start_time                   = "08:00"
        ramp_up_load_balancing_algorithm     = "DepthFirst"
        ramp_up_minimum_hosts_percent        = 5
        ramp_up_capacity_threshold_percent   = 70
        peak_start_time                      = "09:00"
        peak_load_balancing_algorithm        = "DepthFirst"
        ramp_down_start_time                 = "18:00"
        ramp_down_load_balancing_algorithm   = "DepthFirst"
        ramp_down_minimum_hosts_percent      = 5
        ramp_down_capacity_threshold_percent = 50
        ramp_down_force_logoff_users         = false
        ramp_down_wait_time_minutes          = 15
        ramp_down_notification_message       = "This desktop will be shutting down for maintenance in 15 minutes, please save your work and log out immediately."
        ramp_down_stop_hosts_when            = "ZeroActiveSessions"
        off_peak_start_time                  = "19:00"
        off_peak_load_balancing_algorithm    = "DepthFirst"
      }
    }
  }
}
```

## AZURE IMAGE BUILDER CONFIGURATION (Custom VM Images)

```hcl
aib_config = {
  enabled = true
  
  # Storage configuration for build artifacts
  enable_file_share        = true
  file_share_quota_gb      = 100
  enable_private_endpoints = false

  # Image replication regions
  replication_regions = ["UK South", "UK West"]

  # Custom image definitions
  images = {
    "avd-win11-m365" = {
      name        = "avd-win11-m365"
      description = "Windows 11 Multi-session with Microsoft 365 Apps for AVD - Production"
      os_type     = "Windows"

      # VM specifications for building
      vm_size               = "Standard_E2as_v6"  # Sufficient for image building
      os_disk_size_gb       = 127
      build_timeout_minutes = 300                 # 5 hour timeout

      # Image specifications
      hyper_v_generation          = "V2"
      trusted_launch_supported    = true
      enable_nvme_disk_controller = true

      # Source image from marketplace
      publisher = "MicrosoftWindowsDesktop"
      offer     = "office-365"
      sku       = "win11-24h2-avd-m365"
      version   = "latest"

      # Custom build steps (Windows Updates and optimizations)
      customizations = [
        {
          type           = "WindowsUpdate"
          name           = "Install-WindowsUpdates"
          searchCriteria = "IsInstalled=0"
          filters        = [
            "exclude:$_.Title -like '*Preview*'",
            "exclude:$_.KBArticleIDs -Contains '5040442'",
            "include:$true"
          ]
          updateLimit = 20
        },
        {
          type           = "WindowsRestart"
          name           = "Restart-AfterUpdates"
          restartTimeout = "10m"
        }
      ]
    }
  }
}
```

## TERRAFORM BACKEND CONFIGURATION (Remote State)

Optional configuration for storing Terraform state remotely in Azure Storage:

```hcl
backend_config = {
  enabled              = true                           # Enable remote backend
  # resource_group_name  = "rg-prod-terraform-state-uks"  # Resource group for state storage (Override computed naming if needed)
  # storage_account_name = "stprodtfstateuks"             # Storage account name (must be globally unique)
  container_name       = "tfstate"                      # Blob container for state files
  key                  = "azure-landing-zone.tfstate"   # State file name
}
```

## NETWORK ACCESS CONTROL (IP Allowlisting)

The landing zone automatically detects your current public IP address and adds it to the allow list for secure administrative access to storage accounts and other resources with network restrictions.

**Automatic IP Detection**: Your current IP is automatically fetched using Terraform's HTTP data source and added to all network access control lists.

Add additional static IP addresses as needed:

```hcl
# Additional static IPs for administrative access
# Your current IP is automatically detected and added
allow_list_ip = [
  "203.0.113.1/32",    # Example: Office public IP
  "203.0.113.100/32"   # Example: Additional admin IP
]
```

**How it works:**

- The `data "http" "ip"` data source in `data.tf` automatically fetches your current IP from <https://api.ipify.org/>
- Your current IP is combined with any static IPs you define in `allow_list_ip`
- This combined list is used for **all storage account network access controls** throughout the deployment
- **All Azure Storage accounts** (AIB, AVD FSLogix, and Spoke storage) automatically inherit this allow list
- The data source includes retry logic with exponential backoff for reliability
- Each IP address is validated using regex pattern to ensure proper format

**Storage accounts protected:**

- ✅ **AIB Storage**: Image Builder storage accounts for scripts and logs
- ✅ **AVD Storage**: FSLogix profile storage accounts  
- ✅ **Spoke Storage**: General-purpose storage accounts in identity and infrastructure workloads
- 🔒 **Default Action**: All storage accounts deny public access by default and only allow listed IPs

**To check your current IP manually:**

```bash
curl -s https://ipinfo.io/ip
# or
curl -s https://api.ipify.org/
```

## MINIMAL CONFIGURATION EXAMPLES

### FOUNDATION ONLY (Core + Management + Connectivity)

Uncomment and use this minimal config for initial deployment:

```hcl
# core_config = { enabled = true }
# management_config = { enabled = true }
# connectivity_config = {
#   enabled = true
#   hub_virtual_network = {
#     address_space = ["10.0.0.0/16"]
#     subnets = {}  # Use defaults
#   }
#   firewall = { sku_tier = "Standard" }
#   bastion = { enabled = true, subnet_address_prefix = "10.0.1.0/24" }
# }
# identity_config = { enabled = false }
# infra_config = { enabled = false }
# avd_config = { enabled = false }
# aib_config = { enabled = false }
```

### SINGLE SUBSCRIPTION CONFIGURATION

Set all subscription IDs to the same value:

```hcl
# management_subscription_id   = "12345678-1234-1234-1234-123456789012"
# connectivity_subscription_id = "12345678-1234-1234-1234-123456789012"
# identity_subscription_id     = "12345678-1234-1234-1234-123456789012"
# infra_subscription_id        = "12345678-1234-1234-1234-123456789012"
# avd_subscription_id          = "12345678-1234-1234-1234-123456789012"
# aib_subscription_id          = "12345678-1234-1234-1234-123456789012"
```
