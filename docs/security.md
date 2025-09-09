# Security Guide

This document outlines security best practices and configurations for the Azure Landing Zone implementation, including advanced VM security with multiple NICs and data disks.

## Security Architecture

The Azure Landing Zone implements a **Zero Trust security model** with defense-in-depth principles:

- 🔐 **Identity Security**: Azure AD integration with conditional access
- 🛡️ **Network Security**: Network segmentation and micro-segmentation
- 🔒 **Data Protection**: Encryption at rest and in transit
- 📊 **Monitoring**: Comprehensive logging and threat detection
- 🔧 **Infrastructure Security**: Hardened VMs and secure configurations

## Network Security

### Hub-Spoke Network Isolation

```hcl
# Network segmentation with Azure Firewall
connectivity_config = {
  firewall = {
    enabled = true
    sku = {
      tier = "Premium"    # Advanced threat protection
    }
    
    # Threat intelligence and intrusion detection
    threat_intelligence_mode = "Alert"
    intrusion_detection_mode = "Alert"
    
    # DNS proxy for secure name resolution
    dns_proxy_enabled = true
  }
}
```

### Network Security Groups (NSG)

```hcl
# Multi-tier application security rules
security_rules = {
  "AllowWebInbound" = {
    name                    = "AllowWebInbound"
    priority                = 1000
    direction               = "Inbound"
    access                  = "Allow"
    protocol                = "Tcp"
    source_port_range       = "*"
    destination_port_ranges = ["443"]          # HTTPS only
    source_address_prefix   = "Internet"
    destination_address_prefix = "10.20.1.0/24"  # Web tier only
  }
  
  "AllowAppTierFromWeb" = {
    name                     = "AllowAppTierFromWeb"
    priority                 = 1100
    direction                = "Inbound"
    access                   = "Allow"
    protocol                 = "Tcp"
    source_port_range        = "*"
    destination_port_ranges  = ["8443"]        # Encrypted app communication
    source_address_prefixes  = ["10.20.1.0/24"]  # From web tier only
    destination_address_prefix = "10.20.2.0/24"   # To app tier only
  }
  
  "AllowDatabaseFromApp" = {
    name                     = "AllowDatabaseFromApp"
    priority                 = 1200
    direction                = "Inbound"
    access                   = "Allow"
    protocol                 = "Tcp"
    source_port_range        = "*"
    destination_port_ranges  = ["1433"]        # SQL Server TLS
    source_address_prefixes  = ["10.20.2.0/24"]  # From app tier only
    destination_address_prefix = "10.20.3.0/24"   # To data tier only
  }
  
  "DenyDirectDatabaseAccess" = {
    name                    = "DenyDirectDatabaseAccess"
    priority                = 1300
    direction               = "Inbound"
    access                  = "Deny"
    protocol                = "*"
    source_port_range       = "*"
    destination_port_range  = "*"
    source_address_prefix   = "Internet"
    destination_address_prefix = "10.20.3.0/24"  # Protect database tier
  }
}
```

### Private Endpoints

```hcl
# Force all PaaS services through private endpoints
key_vault_config = {
  public_network_access_enabled = false
  enable_private_endpoint       = true
  private_endpoint_subnet_id    = "/subscriptions/.../subnets/snet-private-endpoints"
  
  network_acls = {
    bypass         = "AzureServices"
    default_action = "Deny"
    virtual_network_subnet_ids = [
      "/subscriptions/.../subnets/snet-secure-admin"
    ]
  }
}

storage_config = {
  public_network_access_enabled = false
  enable_private_endpoints      = true
  private_endpoint_subnet_id    = "/subscriptions/.../subnets/snet-private-endpoints"
}
```

## Virtual Machine Security

### Secure VM Configuration

```hcl
virtual_machines = {
  "secure-server" = {
    # Security-hardened VM configuration
    vm_size            = "Standard_D4s_v5"
    os_type            = "Windows"
    os_sku             = "2022-datacenter-g2"      # Generation 2 for security features
    availability_zones = ["1", "2"]                # High availability
    
    # Multiple NICs for security segmentation
    network_interfaces = [
      {
        subnet_name                   = "snet-secure-app"     # Application traffic
        enable_accelerated_networking = true
        private_ip_allocation_method  = "Static"
        static_ip_address            = "10.30.1.10"
      },
      {
        subnet_name                   = "snet-secure-mgmt"    # Management traffic only
        enable_accelerated_networking = false
        private_ip_allocation_method  = "Dynamic"
      }
    ]
    
    # Encrypted data disks with customer-managed keys
    data_disks = [
      {
        size_gb                = 512
        caching                = "ReadWrite"
        storage_account_type   = "Premium_LRS"
        lun                    = 0
        disk_encryption_set_id = "/subscriptions/.../diskEncryptionSets/secure-key"
        write_accelerator_enabled = false
      }
    ]
  }
}
```

### VM Security Features

The module automatically enables advanced security features:

```terraform
# Automatically configured security features
managed_identities = {
  system_assigned = true    # For Azure service authentication
}

encryption_at_host_enabled = true    # Double encryption
secure_boot_enabled        = true    # UEFI Secure Boot
vtpm_enabled              = true     # Virtual TPM
boot_diagnostics          = true     # Security monitoring

# Security extensions
extensions = {
  azure_monitor_agent = {
    # Monitoring and threat detection
    type = "AzureMonitorWindowsAgent"
  }
}
```

### Disk Encryption

```hcl
# Customer-managed encryption keys
resource "azurerm_disk_encryption_set" "security" {
  name                = "secure-disk-encryption"
  resource_group_name = azurerm_resource_group.security.name
  location            = azurerm_resource_group.security.location
  key_vault_key_id    = azurerm_key_vault_key.disk_encryption.id

  identity {
    type = "SystemAssigned"
  }
}

# Apply to data disks
data_disks = [
  {
    disk_encryption_set_id = azurerm_disk_encryption_set.security.id
    # ... other disk configuration
  }
]
```

## Identity and Access Management

### Azure AD Integration

```hcl
# Domain controllers with secure configuration
identity_config = {
  deploy_virtual_machines = true
  
  virtual_machines = {
    "dc" = {
      # Security-focused domain controller configuration
      network_interfaces = [
        {
          subnet_name                   = "snet-identity-secure"
          private_ip_allocation_method  = "Static"
          enable_accelerated_networking = false  # Security over performance
        }
      ]
      
      # Separate disk for AD DS database (security requirement)
      data_disks = [
        {
          size_gb              = 256
          caching              = "None"           # Critical for AD DS integrity
          storage_account_type = "Premium_LRS"
          lun                  = 0
          disk_encryption_set_id = "/subscriptions/.../diskEncryptionSets/ad-key"
        }
      ]
    }
  }
  
  # Secure Key Vault for domain credentials
  enable_key_vault = true
  key_vault_config = {
    sku_name                 = "premium"        # Hardware Security Module
    purge_protection_enabled = true            # Prevent accidental deletion
    
    public_network_access_enabled = false
    enable_private_endpoint       = true
    
    network_acls = {
      default_action = "Deny"
      ip_rules       = []                      # No internet access
      virtual_network_subnet_ids = [
        "/subscriptions/.../subnets/snet-identity-secure"
      ]
    }
  }
}
```

### Role-Based Access Control (RBAC)

```hcl
# Principle of least privilege
default_tags = {
  DataClassification = "Confidential"
  SecurityZone      = "Restricted"
  AccessLevel       = "AuthenticatedUsers"
  BackupRequired    = "true"
  MonitoringLevel   = "Enhanced"
}
```

## Data Protection

### Backup Security

```hcl
backup_config = {
  sku                           = "Standard"
  storage_mode_type             = "GeoRedundant"      # Geographic redundancy
  cross_region_restore_enabled  = true               # Disaster recovery
  immutability                  = "Locked"           # Immutable backups
  
  # Enhanced security for backup vault
  public_network_access_enabled = false
  
  backup_policy = {
    name            = "security-backup-policy"
    policy_type     = "V2"                            # Enhanced backup policy
    retention_daily = 90                              # Extended retention
    
    # Long-term retention for compliance
    retention_yearly = {
      count    = 10                                   # 10 years for compliance
      weekdays = ["Sunday"]
      weeks    = ["First"]
      months   = ["January"]
    }
  }
}
```

### Storage Security

**🔒 Centralized Storage Network Access Control**

All Azure Storage accounts in the landing zone use a **standardized security model** with centralized IP allow lists:

```hcl
# Global allow list configuration (automatically applied to ALL storage accounts)
allow_list_ip = [
  "203.0.113.1/32",    # Office public IP
  "203.0.113.100/32"   # Additional admin IP
]
```

**✅ Storage Accounts Protected:**

- **AIB Storage**: Image Builder storage for scripts and logs
- **AVD Storage**: FSLogix profile storage accounts  
- **Spoke Storage**: General-purpose storage in identity/infrastructure workloads

**🛡️ Security Configuration Applied to All Storage Accounts:**

```hcl
# Standardized network security (applied automatically)
network_rules = {
  default_action = "Deny"                            # Deny all by default
  bypass         = ["AzureServices", "Metrics", "Logging"] # Allow Azure services
  ip_rules       = var.allow_list_ip                 # Your IPs + auto-detected current IP
  virtual_network_subnet_ids = [...]                 # Subnet access for workloads
}

# Security hardening features
min_tls_version                 = "TLS1_2"          # Minimum TLS version
allow_nested_items_to_be_public = false             # No public containers
shared_access_key_enabled       = true              # Enable for service access
```

**🔍 IP Validation**: All IP addresses are validated using regex patterns to ensure proper format (supports both single IPs and CIDR blocks).

## Monitoring and Compliance

### Security Monitoring

```hcl
# Log Analytics workspace for security monitoring
management_config = {
  log_analytics = {
    retention_in_days = 90                           # Extended retention for security
    sku              = "PerGB2018"
    
    # Security-focused log categories
    solutions = [
      "Security",
      "SecurityCenterFree",
      "AzureActivity",
      "VMInsights"
    ]
  }
}
```

### Microsoft Defender Integration

```hcl
# Automatically deployed via Azure Policy
# No configuration needed - enabled by default for:
# - Virtual Machines
# - Key Vault
# - Storage Accounts
# - Azure SQL Database
# - Container Registries
```

## Security Policies

### Built-in Security Policies

The landing zone automatically applies security policies:

```yaml
Applied Policies:
- Deploy Azure Monitor Agent to VMs
- Enable backup for tagged VMs  
- Require private endpoints for storage
- Enable disk encryption for VMs
- Deploy Microsoft Defender for Cloud
- Enforce HTTPS for web applications
- Require secure transfer for storage accounts
- Enable diagnostic logs for Key Vault
- Require TLS 1.2 minimum version
```

### Custom Security Policies

```hcl
core_config = {
  # Custom security policy assignments
  custom_policy_assignments = {
    "enforce-vm-security" = {
      display_name         = "Enforce VM Security Configuration"
      description          = "Ensures VMs meet security baseline"
      policy_definition_id = "/providers/Microsoft.Authorization/policySetDefinitions/vm-security-baseline"
      scope               = "/subscriptions/${var.management_subscription_id}"
      
      parameters = {
        "requireSecureBoot" = {
          value = true
        }
        "requireVTPM" = {
          value = true
        }
        "requireEncryption" = {
          value = true
        }
      }
    }
  }
}
```

## Security Checklist

### Pre-Deployment Security

- [ ] **Network Design**: Proper subnet segmentation planned
- [ ] **Access Control**: RBAC assignments defined
- [ ] **Encryption**: Customer-managed keys prepared
- [ ] **Monitoring**: Log Analytics workspace configured
- [ ] **Policies**: Security policy assignments reviewed

### Post-Deployment Security

- [ ] **VM Security**: Secure Boot and vTPM enabled
- [ ] **Disk Encryption**: All disks encrypted with customer keys
- [ ] **Network Isolation**: NSG rules blocking unnecessary access
- [ ] **Private Endpoints**: All PaaS services using private endpoints
- [ ] **Backup Security**: Immutable backups configured
- [ ] **Monitoring**: Security logs flowing to Log Analytics
- [ ] **Defender**: Microsoft Defender for Cloud enabled

### Ongoing Security Operations

- [ ] **Regular Updates**: Security patches applied monthly
- [ ] **Access Review**: RBAC permissions reviewed quarterly
- [ ] **Key Rotation**: Encryption keys rotated annually
- [ ] **Backup Testing**: Recovery procedures tested quarterly
- [ ] **Compliance**: Security policies compliance monitored
- [ ] **Incident Response**: Security incident procedures documented

## Security Compliance

### Regulatory Compliance

The landing zone supports compliance with:

- **SOC 2**: System and Organization Controls
- **ISO 27001**: Information Security Management
- **GDPR**: General Data Protection Regulation  
- **HIPAA**: Health Insurance Portability and Accountability Act
- **PCI DSS**: Payment Card Industry Data Security Standard

### Compliance Features

```hcl
# Tags for compliance tracking
default_tags = {
  ComplianceFramework = "SOC2,ISO27001,GDPR"
  DataRetention      = "7years"
  EncryptionRequired = "true"
  BackupRequired     = "true"
  MonitoringLevel    = "Enhanced"
  SecurityZone       = "Restricted"
}
```

## Incident Response

### Security Monitoring

```bash
# Query security events in Log Analytics
SecurityEvent
| where EventID in (4625, 4648, 4719, 4720)  // Failed logins, privilege escalation
| where TimeGenerated > ago(24h)
| summarize count() by Computer, EventID
```

### Threat Hunting

```bash
# Hunt for lateral movement
SecurityEvent
| where EventID == 4624  // Successful logon
| where LogonType in (3, 10)  // Network, RemoteInteractive
| where TimeGenerated > ago(7d)
| summarize LoginCount = count() by Account, Computer
| where LoginCount > 50
```

## Best Practices Summary

1. **Network Segmentation**: Use multiple NICs and subnets for security zones
2. **Encryption Everywhere**: Customer-managed keys for all data at rest
3. **Zero Trust Model**: Verify every access request regardless of location
4. **Immutable Backups**: Protect against ransomware with locked backups
5. **Continuous Monitoring**: Comprehensive logging and alerting
6. **Regular Updates**: Keep all systems patched and updated
7. **Compliance Automation**: Use policies to enforce security requirements
8. **Incident Preparedness**: Have documented response procedures

For more detailed security configurations, see the [Configuration Guide](CONFIGURATION.md) and [Operations Guide](OPERATIONS.md).
