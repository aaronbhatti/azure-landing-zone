# Spoke Workloads Guide

This guide demonstrates how to add application workloads to your Azure Landing Zone using the flexible spoke module with advanced VM configurations including multiple NICs and data disks.

## Overview

The Azure Landing Zone uses a **hub-spoke architecture** where:

- **Hub**: Central networking, security, and connectivity services
- **Spokes**: Individual workloads with dedicated virtual networks and resources
- **Workload Types**: Different spoke configurations for various application patterns

## Spoke Module Capabilities

### Advanced VM Features

- **Multiple NICs**: Network segmentation and security isolation
- **Multiple Data Disks**: Performance optimization and data separation
- **High Availability**: Availability zones and clustering support
- **Microsoft Naming**: Zero-padded naming conventions (nic01, datadisk01)
- **Enterprise Security**: Encryption, monitoring, and compliance

### Supported Workload Roles

- `app`: Application workloads and web services
- `data`: Database and data platform services
- `dev`: Development and testing environments
- `security`: Security and compliance services
- `identity`: Active Directory and identity services
- `infra`: Infrastructure and shared services

## Workload Examples

### 1. Three-Tier Web Application

A complete web application with presentation, application, and data tiers:

```hcl
# Three-tier application spoke
module "web_application" {
  source = "./modules/spoke"

  providers = {
    azurerm.spoke        = azurerm.app
    azurerm.connectivity = azurerm.connectivity
  }

  org_name        = var.org_name
  environment     = var.environment
  location        = var.location
  subscription_id = var.app_subscription_id
  workload_role   = "app"

  spoke_config = {
    resource_group_name = "rg-webapp-${var.environment}-${local.location_abbr}"

    # Network segmentation for security
    virtual_network = {
      name          = "vnet-webapp-${var.environment}-${local.location_abbr}"
      address_space = ["10.20.0.0/16"]
      
      subnets = {
        "snet-web-tier" = {
          address_prefixes = ["10.20.1.0/24"]    # Web servers (DMZ)
        }
        "snet-app-tier" = {
          address_prefixes = ["10.20.2.0/24"]    # Application servers
        }
        "snet-data-tier" = {
          address_prefixes = ["10.20.3.0/24"]    # Database servers
        }
        "snet-mgmt" = {
          address_prefixes = ["10.20.5.0/24"]    # Management and monitoring
        }
        "snet-private-endpoints" = {
          address_prefixes = ["10.20.10.0/24"]   # Private endpoints
        }
      }
    }

    # Multi-tier VMs with different configurations
    deploy_virtual_machines = true
    virtual_machines = {
      # Web Tier - Public-facing servers
      "web" = {
        count              = 3                   # Load balanced web servers
        vm_size            = "Standard_D4s_v5"
        os_type            = "Windows"
        availability_zones = ["1", "2", "3"]
        vm_name_prefix     = "WEB"
        
        # Dual NIC for web tier
        network_interfaces = [
          {
            subnet_name                   = "snet-web-tier"   # Internet-facing
            enable_accelerated_networking = true
            private_ip_allocation_method  = "Static"
          },
          {
            subnet_name                   = "snet-app-tier"   # Backend communication
            enable_accelerated_networking = true
            private_ip_allocation_method  = "Dynamic"
          }
        ]
        
        # Web server storage
        data_disks = [
          {
            size_gb              = 512              # Web content and cache
            storage_account_type = "Premium_LRS"
            lun                  = 0
          },
          {
            size_gb              = 256              # IIS logs
            storage_account_type = "StandardSSD_LRS"
            lun                  = 1
          }
        ]
      }
      
      # Application Tier - Business logic
      "app" = {
        count              = 2                   # High availability
        vm_size            = "Standard_E8s_v5"  # Memory-optimized
        os_type            = "Windows"
        availability_zones = ["1", "2"]
        vm_name_prefix     = "APP"
        
        # Triple NIC for application tier
        network_interfaces = [
          {
            subnet_name                   = "snet-app-tier"   # Primary app network
            enable_accelerated_networking = true
            private_ip_allocation_method  = "Static"
          },
          {
            subnet_name                   = "snet-data-tier"  # Database communication
            enable_accelerated_networking = true
            private_ip_allocation_method  = "Dynamic"
          },
          {
            subnet_name                   = "snet-mgmt"       # Management access
            enable_accelerated_networking = false
            private_ip_allocation_method  = "Dynamic"
          }
        ]
        
        # Application server storage
        data_disks = [
          {
            size_gb              = 1024             # Application data
            storage_account_type = "Premium_LRS"
            lun                  = 0
          },
          {
            size_gb              = 512              # Application cache
            storage_account_type = "Premium_LRS"
            lun                  = 1
          },
          {
            size_gb              = 256              # Application logs
            storage_account_type = "StandardSSD_LRS"
            lun                  = 2
          }
        ]
      }
      
      # Database Tier - Data persistence
      "db" = {
        count              = 2                   # Always On Availability Group
        vm_size            = "Standard_E16s_v5" # High-performance database
        os_type            = "Windows"
        availability_zones = ["1", "2"]
        vm_name_prefix     = "DB"
        
        # Database networking
        network_interfaces = [
          {
            subnet_name                   = "snet-data-tier"  # Primary database network
            enable_accelerated_networking = true
            private_ip_allocation_method  = "Static"
          },
          {
            subnet_name                   = "snet-mgmt"       # Management and backup
            enable_accelerated_networking = false
            private_ip_allocation_method  = "Dynamic"
          }
        ]
        
        # High-performance database storage
        data_disks = [
          {
            size_gb                   = 2048        # Database files (MDF)
            caching                   = "None"      # Critical for SQL Server
            storage_account_type      = "Premium_LRS"
            lun                       = 0
            write_accelerator_enabled = true        # Ultra-high IOPS
          },
          {
            size_gb                   = 1024        # Transaction logs (LDF)
            caching                   = "None"      # Critical for consistency
            storage_account_type      = "Premium_LRS"
            lun                       = 1
            write_accelerator_enabled = true
          },
          {
            size_gb                   = 512         # TempDB
            storage_account_type      = "Premium_LRS"
            lun                       = 2
          }
        ]
      }
    }

    # Application-specific security rules
    security_rules = {
      "AllowWebTraffic" = {
        name                    = "AllowWebTraffic"
        priority                = 1000
        direction               = "Inbound"
        access                  = "Allow"
        protocol                = "Tcp"
        destination_port_ranges = ["443"]          # HTTPS only
        source_address_prefix   = "Internet"
      }
      
      "AllowAppCommunication" = {
        name                     = "AllowAppCommunication"
        priority                 = 1100
        direction                = "Inbound"
        access                   = "Allow"
        protocol                 = "Tcp"
        destination_port_ranges  = ["8443"]        # Encrypted app communication
        source_address_prefixes  = ["10.20.1.0/24"] # From web tier
      }
    }

    # Enterprise features
    connect_to_hub   = true
    enable_storage   = true
    enable_backup    = true
    enable_key_vault = true
  }

  # Hub connectivity
  hub_virtual_network_id     = module.connectivity.hub_virtual_network_id
  hub_virtual_network_name   = module.connectivity.hub_virtual_network_name
  hub_resource_group_name    = module.connectivity.hub_resource_group_name
  log_analytics_workspace_id = module.management[0].log_analytics_workspace_id
  firewall_private_ip        = module.connectivity.firewall_private_ip

  default_tags = merge(var.default_tags, {
    WorkloadType    = "three-tier-web-app"
    CriticalityTier = "High"
    Environment     = var.environment
  })

  enable_telemetry = var.enable_telemetry
}
```

**Expected Resource Names:**

- Web Servers: `WEB01`, `WEB02`, `WEB03`
  - NICs: `WEB01-nic01` (web), `WEB01-nic02` (app)
  - Disks: `WEB01-datadisk01` (content), `WEB01-datadisk02` (logs)
- App Servers: `APP01`, `APP02`
  - NICs: `APP01-nic01` (app), `APP01-nic02` (data), `APP01-nic03` (mgmt)
  - Disks: `APP01-datadisk01` (data), `APP01-datadisk02` (cache), `APP01-datadisk03` (logs)
- Database Servers: `DB01`, `DB02`
  - NICs: `DB01-nic01` (data), `DB01-nic02` (mgmt)
  - Disks: `DB01-datadisk01` (MDF), `DB01-datadisk02` (LDF), `DB01-datadisk03` (TempDB)

### 2. Development Environment

Cost-optimized development environment with shared resources:

```hcl
module "development" {
  source = "./modules/spoke"

  providers = {
    azurerm.spoke        = azurerm.dev
    azurerm.connectivity = azurerm.connectivity
  }

  org_name        = var.org_name
  environment     = "dev"
  location        = var.location
  subscription_id = var.dev_subscription_id
  workload_role   = "dev"

  spoke_config = {
    # Development workloads
    virtual_machines = {
      # Frontend developers
      "fe-dev" = {
        count              = 2
        vm_size            = "Standard_B4ms"      # Burstable for cost optimization
        availability_zones = ["1", "2"]
        vm_name_prefix     = "FE-DEV"
        
        network_interfaces = [
          {
            subnet_name                   = "snet-dev-frontend"
            enable_accelerated_networking = false  # Cost optimization
            private_ip_allocation_method  = "Dynamic"
          }
        ]
        
        data_disks = [
          {
            size_gb              = 256              # Development files
            storage_account_type = "StandardSSD_LRS" # Cost-effective
            lun                  = 0
          }
        ]
      }
      
      # Shared development database
      "dev-db" = {
        count              = 1
        vm_size            = "Standard_D4s_v5"
        availability_zones = ["1"]
        vm_name_prefix     = "DEV-DB"
        
        network_interfaces = [
          {
            subnet_name                   = "snet-dev-database"
            private_ip_allocation_method  = "Static"
          }
        ]
        
        data_disks = [
          {
            size_gb              = 512              # Development database
            storage_account_type = "Premium_LRS"
            lun                  = 0
          }
        ]
      }
    }

    # Relaxed security for development productivity
    security_rules = {
      "AllowDevelopmentAccess" = {
        name                    = "AllowDevelopmentAccess"
        priority                = 1000
        direction               = "Inbound"
        access                  = "Allow"
        protocol                = "Tcp"
        destination_port_ranges = ["80", "443", "3000", "8080"]
        source_address_prefix   = "VirtualNetwork"
      }
    }

    # Cost-optimized features
    enable_backup    = false                      # Skip backup for dev
    enable_key_vault = false                      # Not critical for dev
  }
}
```

### 3. High-Performance Analytics Platform

Data analytics workload with optimized storage:

```hcl
module "analytics" {
  source = "./modules/spoke"

  workload_role = "data"

  spoke_config = {
    virtual_machines = {
      # Analytics cluster nodes
      "analytics" = {
        count              = 4
        vm_size            = "Standard_E32s_v5"    # Memory-optimized for analytics
        availability_zones = ["1", "2"]
        vm_name_prefix     = "ANALYTICS"
        
        # Multiple NICs for data ingestion and processing
        network_interfaces = [
          {
            subnet_name                   = "snet-analytics-processing"
            enable_accelerated_networking = true
            private_ip_allocation_method  = "Static"
          },
          {
            subnet_name                   = "snet-analytics-storage"
            enable_accelerated_networking = true
            private_ip_allocation_method  = "Dynamic"
          },
          {
            subnet_name                   = "snet-analytics-mgmt"
            enable_accelerated_networking = false
            private_ip_allocation_method  = "Dynamic"
          }
        ]
        
        # High-performance storage for analytics
        data_disks = [
          {
            size_gb                   = 4096        # Hot data storage
            storage_account_type      = "Premium_LRS"
            lun                       = 0
            write_accelerator_enabled = true        # Maximum IOPS
          },
          {
            size_gb                   = 8192        # Warm data storage
            storage_account_type      = "Premium_LRS"
            lun                       = 1
          },
          {
            size_gb                   = 2048        # Processing cache
            storage_account_type      = "Premium_LRS"
            lun                       = 2
          },
          {
            size_gb                   = 1024        # Results and exports
            storage_account_type      = "StandardSSD_LRS"
            lun                       = 3
          }
        ]
      }
    }
  }
}
```

### 4. Microservices Container Platform

Container-based microservices with AKS integration:

```hcl
module "microservices" {
  source = "./modules/spoke"

  workload_role = "app"

  spoke_config = {
    # Container host VMs for hybrid scenarios
    virtual_machines = {
      "container-host" = {
        count              = 3
        vm_size            = "Standard_D8s_v5"
        availability_zones = ["1", "2", "3"]
        vm_name_prefix     = "CONTAINER"
        
        # Container networking
        network_interfaces = [
          {
            subnet_name                   = "snet-container-nodes"
            enable_accelerated_networking = true
            private_ip_allocation_method  = "Dynamic"
          },
          {
            subnet_name                   = "snet-container-services"
            enable_accelerated_networking = true
            private_ip_allocation_method  = "Dynamic"
          }
        ]
        
        # Container storage
        data_disks = [
          {
            size_gb              = 1024             # Container images and volumes
            storage_account_type = "Premium_LRS"
            lun                  = 0
          },
          {
            size_gb              = 512              # Container logs
            storage_account_type = "StandardSSD_LRS"
            lun                  = 1
          }
        ]
      }
    }

    # Additional subnets for AKS integration
    virtual_network = {
      subnets = {
        "snet-aks-nodes" = {
          address_prefixes = ["10.30.1.0/24"]
        }
        "snet-aks-pods" = {
          address_prefixes = ["10.30.2.0/23"]     # Larger subnet for pods
        }
        "snet-aks-services" = {
          address_prefixes = ["10.30.10.0/24"]
        }
      }
    }
  }
}
```

## Best Practices

### Network Segmentation

1. **Use Multiple NICs** for security isolation:
   - Separate management traffic from application traffic
   - Isolate database communication from web traffic
   - Use dedicated backup and replication networks

2. **Subnet Design**:

   ```hcl
   subnets = {
     "snet-web-tier"         = { address_prefixes = ["10.x.1.0/24"] }   # DMZ
     "snet-app-tier"         = { address_prefixes = ["10.x.2.0/24"] }   # Internal apps
     "snet-data-tier"        = { address_prefixes = ["10.x.3.0/24"] }   # Databases
     "snet-mgmt"             = { address_prefixes = ["10.x.5.0/24"] }   # Management
     "snet-backup"           = { address_prefixes = ["10.x.6.0/24"] }   # Backup traffic
     "snet-private-endpoints" = { address_prefixes = ["10.x.10.0/24"] }  # Private endpoints
   }
   ```

### Storage Optimization

1. **Disk Configuration by Workload**:

   ```hcl
   # Database server (SQL Server)
   data_disks = [
     {
       size_gb                   = 2048
       caching                   = "None"         # Database files
       storage_account_type      = "Premium_LRS"
       write_accelerator_enabled = true
       lun                       = 0
     },
     {
       size_gb                   = 1024
       caching                   = "None"         # Transaction logs
       storage_account_type      = "Premium_LRS"
       write_accelerator_enabled = true
       lun                       = 1
     }
   ]
   
   # Web server
   data_disks = [
     {
       size_gb              = 512
       caching              = "ReadWrite"         # Web content
       storage_account_type = "Premium_LRS"
       lun                  = 0
     }
   ]
   ```

2. **Storage Performance Tiers**:
   - **Premium_LRS**: High-performance workloads (databases, applications)
   - **StandardSSD_LRS**: Balanced performance and cost (logs, temp files)
   - **Standard_LRS**: Cost-optimized (backups, archives)

### High Availability

1. **Availability Zones**:

   ```hcl
   # Distribute VMs across zones
   availability_zones = ["1", "2", "3"]
   ```

2. **Load Balancing**:

   ```hcl
   # Multiple instances for load distribution
   count = 3    # Odd number for quorum-based applications
   ```

### Security Considerations

1. **Network Security Groups**:
   - Implement least-privilege access
   - Use application-specific ports
   - Block unnecessary internet access

2. **Encryption**:

   ```hcl
   # Customer-managed encryption
   disk_encryption_set_id = "/subscriptions/.../diskEncryptionSets/workload-key"
   ```

3. **Private Endpoints**:

   ```hcl
   enable_key_vault = true
   key_vault_config = {
     public_network_access_enabled = false
     enable_private_endpoint       = true
   }
   ```

## Deployment Workflow

### 1. Plan Your Workload

- Define network requirements and segmentation
- Choose appropriate VM sizes and storage types
- Plan for high availability and disaster recovery
- Consider compliance and security requirements

### 2. Create Configuration

```bash
# Copy example configuration
cp environments/prod.tfvars environments/my-workload.tfvars

# Edit with your workload-specific settings
vi environments/my-workload.tfvars
```

### 3. Deploy Workload

```bash
# Deploy the spoke workload
terraform plan -var-file="environments/my-workload.tfvars"
terraform apply -var-file="environments/my-workload.tfvars"
```

### 4. Validate Deployment

- Verify VM creation and naming (following Microsoft conventions)
- Check network connectivity between tiers
- Validate security group rules
- Test application functionality

## Monitoring and Operations

### Resource Naming

All resources follow Microsoft naming conventions:

- VMs: `{PREFIX}01`, `{PREFIX}02` (zero-padded)
- NICs: `{VM-NAME}-nic01`, `{VM-NAME}-nic02`
- Disks: `{VM-NAME}-datadisk01`, `{VM-NAME}-datadisk02`
- OS Disks: `{VM-NAME}-osdisk`

### Monitoring

```hcl
# Automatic monitoring configuration
default_tags = {
  Environment     = var.environment
  WorkloadType    = "application"
  MonitoringLevel = "Standard"
  BackupRequired  = "true"
}
```

### Operations

- **Backup**: Automatic VM backup if `enable_backup = true`
- **Monitoring**: Azure Monitor Agent deployed automatically
- **Security**: Microsoft Defender enabled by default
- **Compliance**: Azure policies applied automatically

For detailed operational procedures, see the [Operations Guide](OPERATIONS.md).

## Next Steps

- [Security Guide](SECURITY.md) - Secure your workloads
- [Operations Guide](OPERATIONS.md) - Day-2 operations
- [Configuration Guide](CONFIGURATION.md) - Advanced configurations
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues and solutions