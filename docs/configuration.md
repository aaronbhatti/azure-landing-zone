# Configuration Guide

This document provides detailed information about configuring the Azure Landing Zone components, including advanced virtual machine configurations with multiple NICs and data disks.

## Core Configuration

### Organization Settings

```hcl
org_name    = "myorg"          # Organization name for resource naming
environment = "prod"           # Environment: dev, test, prod
location    = "UK South"       # Primary Azure region

# Optional: Control automation account deployment (default: true)
enable_automation_account = false
```

### Subscription Configuration

The landing zone supports deployment across multiple subscriptions:

```hcl
management_subscription_id   = "subscription-id"  # Core management resources
connectivity_subscription_id = "subscription-id"  # Networking components  
identity_subscription_id     = "subscription-id"  # Identity resources
avd_subscription_id         = "subscription-id"  # Azure Virtual Desktop
aib_subscription_id         = "subscription-id"  # Azure Image Builder
```

## Component Configuration

### 1. Connectivity Configuration

```hcl
connectivity_config = {
  enabled = true
  
  # Hub Virtual Network
  hub_virtual_network = {
    address_space = ["10.0.0.0/16"]
    subnets = {
      "AzureBastionSubnet" = {
        address_prefixes = ["10.0.1.0/24"]
      }
      "GatewaySubnet" = {
        address_prefixes = ["10.0.2.0/24"]
      }
      "AzureFirewallSubnet" = {
        address_prefixes = ["10.0.3.0/24"]
      }
    }
  }
  
  # Azure Firewall
  firewall = {
    enabled = true
    sku = {
      name = "AZFW_VNet"
      tier = "Standard"  # or "Premium"
    }
  }
  
  # VPN Gateway
  vpn_gateway = {
    enabled = true
    sku     = "VpnGw1"  # VpnGw1, VpnGw2, VpnGw3
  }
  
  # Private DNS Zones
  private_dns = {
    enabled = true
    zones   = [
      "privatelink.database.windows.net",
      "privatelink.blob.core.windows.net"
    ]
  }
  
  # Azure Bastion (secure RDP/SSH access)
  bastion = {
    enabled               = true            # Enable/disable bastion deployment
    subnet_address_prefix = "10.0.1.0/24"  # Must match AzureBastionSubnet above
    sku                   = "Basic"         # Basic or Standard
    zones                 = []              # Basic SKU doesn't support zones
  }
}
```

### 2. Identity Configuration

```hcl
identity_config = {
  enabled                   = true
  
  virtual_network = {
    # name          = "vnet-identity-prod" # Override computed naming if needed
    address_space = ["10.1.0.0/16"]
    subnets = {
      "snet-domain-controllers" = {
        address_prefixes = ["10.1.1.0/24"]
      }
    }
  }
  
  domain_controllers = {
    count           = 2
    vm_size         = "Standard_D4s_v5" 
    static_ip_start = "10.1.1.10"
    
    # Domain Configuration
    domain_name = "myorg.local"
    domain_mode = "WinThreshold"
    forest_mode = "WinThreshold"
  }
  
  # Key Vault Configuration
  enable_key_vault = true
  key_vault_config = {
    sku_name                        = "standard"
    public_network_access_enabled   = false
    enable_private_endpoint         = true
    private_endpoint_subnet_id      = "/subscriptions/.../subnets/private-endpoints"
  }
}
```

### 3. AVD Configuration

```hcl
avd_config = {
  enabled = true
  
  host_pools = {
    "pooled-general" = {
      type               = "Pooled"
      load_balancer_type = "BreadthFirst"
      max_sessions_limit = 8
      
      virtual_network = {
        # name          = "vnet-avd-prod" # Override computed naming if needed
        address_space = ["10.3.0.0/16"]
        subnets = {
          "snet-avd-hosts" = {
            address_prefixes = ["10.3.1.0/24"]
          }
        }
      }
      
      session_hosts = {
        count = 2
        size  = "Standard_D4s_v5"
        source_image = {
          publisher = "MicrosoftWindowsDesktop"
          offer     = "Windows-11"
          sku       = "win11-24h2-avd"
          version   = "latest"
        }
      }
    }
  }
  
  # Scaling Plan Configuration (required for AVD)
  scaling_plan = {
    name      = "avd-scaling-plan"  # Required field for scaling plan
    time_zone = "GMT Standard Time"
    schedules = {
      "weekdays" = {
        days_of_week = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        peak_start_time = "08:00"
        off_peak_start_time = "18:00"
        # ... other schedule settings
      }
    }
  }
}
```

## Security Configuration

### Network Security Rule Priorities

Customize default NSG rule priorities to avoid conflicts:

```hcl
spoke_config = {
  default_security_rule_priorities = {
    azure_cloud_base     = 110   # Azure services outbound
    bastion_inbound      = 160   # Bastion communication
    vnet_inbound_base    = 4000  # VNet traffic
    deny_all_inbound     = 4096  # Deny all (lowest priority)
  }
}
```

### Key Vault Network Security

```hcl
key_vault_config = {
  public_network_access_enabled = false
  network_acls = {
    bypass         = "AzureServices"
    default_action = "Deny"
    ip_rules       = ["203.0.113.1/32"]  # Your office IP
    virtual_network_subnet_ids = [
      "/subscriptions/.../subnets/admin-subnet"
    ]
  }
  enable_private_endpoint = true
}
```

## Virtual Machine Configuration

### Multiple NICs and Data Disks

The spoke module supports advanced VM configurations with multiple network interfaces and data disks following Microsoft naming conventions.

#### Basic VM Configuration

```hcl
virtual_machines = {
  "web-server" = {
    count              = 2
    vm_size            = "Standard_D4s_v5"
    os_type            = "Windows"
    os_sku             = "2022-datacenter"
    admin_username     = "azureadmin"
    os_disk_size_gb    = 256
    availability_zones = ["1", "2"]
    subnet_name        = "snet-web-tier"
    static_ip_start    = "10.20.1.10"
    enable_extensions  = true
    vm_name_prefix     = "WEB"
  }
}
```

#### Multiple Network Interfaces

```hcl
virtual_machines = {
  "app-server" = {
    # ... basic configuration ...
    
    # Multiple network interfaces for network segmentation
    network_interfaces = [
      {
        subnet_name                   = "snet-app-tier"     # Primary application network
        enable_ip_forwarding          = false
        enable_accelerated_networking = true
        private_ip_allocation_method  = "Static"
        static_ip_address             = "10.20.2.10"
      },
      {
        subnet_name                   = "snet-data-tier"    # Database communication
        enable_ip_forwarding          = false
        enable_accelerated_networking = true
        private_ip_allocation_method  = "Dynamic"
      },
      {
        subnet_name                   = "snet-mgmt"         # Management network
        enable_ip_forwarding          = false
        enable_accelerated_networking = false
        private_ip_allocation_method  = "Dynamic"
      }
    ]
  }
}
```

#### Multiple Data Disks

```hcl
virtual_machines = {
  "database-server" = {
    # ... basic configuration ...
    
    # Multiple data disks with different performance characteristics
    data_disks = [
      {
        size_gb                   = 2048                   # Database files (MDF)
        caching                   = "None"                 # Critical for SQL Server
        storage_account_type      = "Premium_LRS"
        create_option             = "Empty"
        lun                       = 0
        write_accelerator_enabled = true                   # Ultra-high IOPS
        disk_encryption_set_id    = "/subscriptions/.../diskEncryptionSets/mykey"
      },
      {
        size_gb                   = 1024                   # Transaction logs (LDF)
        caching                   = "None"                 # Critical for consistency
        storage_account_type      = "Premium_LRS"
        create_option             = "Empty"
        lun                       = 1
        write_accelerator_enabled = true
      },
      {
        size_gb                   = 512                    # TempDB files
        caching                   = "ReadWrite"
        storage_account_type      = "Premium_LRS"
        create_option             = "Empty"
        lun                       = 2
        write_accelerator_enabled = false
      },
      {
        size_gb                   = 256                    # Application logs
        caching                   = "ReadWrite"
        storage_account_type      = "StandardSSD_LRS"      # Cost-effective for logs
        create_option             = "Empty"
        lun                       = 3
        write_accelerator_enabled = false
      }
    ]
  }
}
```

#### Complete Multi-Tier Application Example

```hcl
# Three-tier application with proper network segmentation
virtual_machines = {
  "web" = {
    count              = 3
    vm_size            = "Standard_D4s_v5"
    availability_zones = ["1", "2", "3"]
    vm_name_prefix     = "WEB"
    
    # Dual NIC for web servers
    network_interfaces = [
      {
        subnet_name                   = "snet-web-tier"
        enable_accelerated_networking = true
        private_ip_allocation_method  = "Static"
      },
      {
        subnet_name                   = "snet-app-tier"
        enable_accelerated_networking = true
        private_ip_allocation_method  = "Dynamic"
      }
    ]
    
    # Web server storage
    data_disks = [
      {
        size_gb              = 512      # Web content and cache
        storage_account_type = "Premium_LRS"
        lun                  = 0
      }
    ]
  }
  
  "app" = {
    count              = 2
    vm_size            = "Standard_E8s_v5"     # Memory-optimized
    availability_zones = ["1", "2"]
    vm_name_prefix     = "APP"
    
    # Triple NIC for application servers
    network_interfaces = [
      {
        subnet_name                   = "snet-app-tier"    # Primary app network
        enable_accelerated_networking = true
        private_ip_allocation_method  = "Static"
      },
      {
        subnet_name                   = "snet-data-tier"   # Database communication
        enable_accelerated_networking = true
        private_ip_allocation_method  = "Dynamic"
      },
      {
        subnet_name                   = "snet-mgmt"        # Management
        enable_accelerated_networking = false
        private_ip_allocation_method  = "Dynamic"
      }
    ]
    
    # Application server storage
    data_disks = [
      {
        size_gb              = 1024     # Application data
        storage_account_type = "Premium_LRS"
        lun                  = 0
      },
      {
        size_gb              = 256      # Application logs
        storage_account_type = "StandardSSD_LRS"
        lun                  = 1
      }
    ]
  }
  
  "db" = {
    count              = 2
    vm_size            = "Standard_E16s_v5"    # High-performance database
    availability_zones = ["1", "2"]
    vm_name_prefix     = "DB"
    
    # Database server networking
    network_interfaces = [
      {
        subnet_name                   = "snet-data-tier"   # Primary database network
        enable_accelerated_networking = true
        private_ip_allocation_method  = "Static"
      },
      {
        subnet_name                   = "snet-backup"      # Backup/replication
        enable_accelerated_networking = true
        private_ip_allocation_method  = "Dynamic"
      }
    ]
    
    # High-performance database storage
    data_disks = [
      {
        size_gb                   = 4096    # Database files
        caching                   = "None"
        storage_account_type      = "Premium_LRS"
        lun                       = 0
        write_accelerator_enabled = true
      },
      {
        size_gb                   = 2048    # Transaction logs
        caching                   = "None"
        storage_account_type      = "Premium_LRS"
        lun                       = 1
        write_accelerator_enabled = true
      },
      {
        size_gb                   = 1024    # TempDB
        storage_account_type      = "Premium_LRS"
        lun                       = 2
      }
    ]
  }
}
```

#### Generated Resource Names (Microsoft Standards)

The module follows Microsoft naming conventions with zero-padded numbering:

**Web Servers:**

- VMs: `WEB01`, `WEB02`, `WEB03`
- NICs: `WEB01-nic01`, `WEB01-nic02`
- Data Disks: `WEB01-datadisk01`
- OS Disks: `WEB01-osdisk`

**Application Servers:**

- VMs: `APP01`, `APP02`
- NICs: `APP01-nic01`, `APP01-nic02`, `APP01-nic03`
- Data Disks: `APP01-datadisk01`, `APP01-datadisk02`
- OS Disks: `APP01-osdisk`

**Database Servers:**

- VMs: `DB01`, `DB02`
- NICs: `DB01-nic01`, `DB01-nic02`
- Data Disks: `DB01-datadisk01`, `DB01-datadisk02`, `DB01-datadisk03`
- OS Disks: `DB01-osdisk`

### VM Configuration Options

#### Network Interface Options

| Property | Description | Type | Default |
|----------|-------------|------|---------|
| `subnet_name` | Target subnet name | `string` | Required |
| `enable_ip_forwarding` | Enable IP forwarding | `bool` | `false` |
| `enable_accelerated_networking` | Enable accelerated networking | `bool` | `false` |
| `private_ip_allocation_method` | IP allocation method | `string` | `"Dynamic"` |
| `static_ip_address` | Static IP (if method is Static) | `string` | `null` |

#### Data Disk Options

| Property | Description | Type | Default |
|----------|-------------|------|---------|
| `size_gb` | Disk size in GB | `number` | `256` |
| `caching` | Disk caching policy | `string` | `"ReadWrite"` |
| `storage_account_type` | Storage performance tier | `string` | `"Premium_LRS"` |
| `create_option` | Disk creation method | `string` | `"Empty"` |
| `lun` | Logical unit number | `number` | Required |
| `disk_encryption_set_id` | Customer-managed encryption key | `string` | `null` |
| `write_accelerator_enabled` | Enable Write Accelerator (M-series) | `bool` | `false` |

### Storage Performance Guidelines

| Workload Type | Storage Type | Caching | Write Accelerator |
|---------------|-------------|---------|------------------|
| Web Content | `Premium_LRS` | `ReadWrite` | `false` |
| Application Data | `Premium_LRS` | `ReadWrite` | `false` |
| Database Files (MDF) | `Premium_LRS` | `None` | `true` |
| Transaction Logs (LDF) | `Premium_LRS` | `None` | `true` |
| TempDB | `Premium_LRS` | `ReadWrite` | `false` |
| Application Logs | `StandardSSD_LRS` | `ReadWrite` | `false` |
| Backup Storage | `StandardSSD_LRS` | `ReadWrite` | `false` |

## Advanced Configuration

### Backend Storage

For team collaboration, configure remote state storage:

```hcl
backend_config = {
  enabled              = true
  # resource_group_name  = "terraform-state-rg" # Override computed naming if needed
  # storage_account_name = "tfstatemyorg2024" # Override computed naming if needed
  container_name       = "tfstate"
  key                  = "azure-landing-zone.tfstate"
}
```

### Telemetry

```hcl
enable_telemetry = true  # Enable Azure usage telemetry
```

### Tags

```hcl
default_tags = {
  Environment = "Production"
  Owner       = "Cloud Team"
  CostCenter  = "IT-001"
  Project     = "Azure Landing Zone"
}
```

## Network Access Control

### Storage Account Security

All Azure Storage accounts across the landing zone use **centralized IP allow lists** for network access control:

```hcl
# Global IP allow list - applied to ALL storage accounts automatically
allow_list_ip = [
  "203.0.113.1/32",      # Office public IP
  "203.0.113.100/32"     # Additional admin IP
]
```

**Protected Storage Accounts:**

- ✅ **AIB (Azure Image Builder)**: Script storage and logging
- ✅ **AVD FSLogix**: User profile storage  
- ✅ **Spoke Storage**: Identity and infrastructure workload storage

**Automatic Features:**

- 🔄 **Auto IP Detection**: Your current public IP is automatically detected and added
- 🔐 **Default Deny**: All storage accounts deny public access by default
- ✅ **Subnet Access**: Workload subnets are automatically granted access
- 🔍 **IP Validation**: All IP addresses are validated for proper format

**Network Rules Applied:**

```hcl
network_rules = {
  default_action = "Deny"
  bypass         = ["AzureServices", "Metrics", "Logging"]
  ip_rules       = var.allow_list_ip  # Your IPs + auto-detected current IP
}
```

## Validation

Use `terraform plan` to validate configuration before applying:

```bash
terraform plan -var-file="environments/my-config.tfvars"
```

## Configuration Template

For a complete, copy-paste ready configuration template with all available options, see:
**[Configuration Template](configuration-template.md)**

## Next Steps

- [Spoke Workloads Guide](spoke_workloads.md) - Adding application workloads
- [Security Guide](security.md) - Security best practices  
- [Operations Guide](operations.md) - Day-2 operations
