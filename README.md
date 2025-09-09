# Azure Landing Zone

A modern, enterprise-ready Terraform implementation of Azure Landing Zones using **Azure Verified Modules (AVM)** with enhanced security, monitoring, and Well-Architected Framework alignment. Supports complex virtual machine configurations with multiple NICs and data disks following Microsoft naming conventions.

## Overview

This repository provides a comprehensive Azure Landing Zone implementation featuring:

- **🏛️ Core Governance**: Microsoft's official ALZ pattern modules with custom management group names and hierarchy support
- **⚙️ Management Layer**: Log Analytics, optional Automation Account, and monitoring infrastructure with full diagnostic settings
- **🔧 Infrastructure Layer**: Modern Azure Verified Modules with enhanced VM capabilities
- **🖥️ Advanced VM Support**: Multiple NICs, multiple data disks, high availability configurations
- **🛡️ Enterprise Backup**: Pre-configured Recovery Services Vaults with tiered backup policies for VMs and Azure Files
- **🔒 Security-First**: Zero Trust architecture with centralized storage access control, private endpoints, and enhanced encryption
- **📊 Multi-Subscription**: Flexible deployment across single or multiple subscriptions
- **📏 Microsoft Standards**: Follows official Azure naming conventions and best practices

## Quick Start

**New to Azure Landing Zones?** Start here: **[📚 Quick Start Guide](docs/quick_start.md)**

```bash
git clone <repository-url>
cd azure-landing-zone
cp environments/prod.tfvars environments/my-deployment.tfvars
# Edit my-deployment.tfvars with your settings
terraform init
terraform plan -var-file="environments/my-deployment.tfvars"
terraform apply -var-file="environments/my-deployment.tfvars"
```

## Documentation

| Guide | Description |
|-------|-------------|
| **[🚀 Quick Start](docs/quick_start.md)** | Get started in under 30 minutes |
| **[⚙️ Configuration](docs/configuration.md)** | Detailed configuration reference |
| **[📋 Configuration Template](docs/configuration-template.md)** | Complete configuration template (copy-paste ready) |
| **[📄 Environment Templates](docs/environment-templates.md)** | Reusable templates for different environments |
| **[🏛️ Custom Architecture](docs/custom_architecture.md)** | Custom management group names and hierarchy |
| **[🔐 Security](docs/security.md)** | Security best practices |
| **[🏷️ Tagging Standards](docs/tagging-standards.md)** | Automated tag inheritance policies |
| **[🛡️ Backup Policies](docs/backup-policies.md)** | Default backup policies and Azure Policy requirements |
| **[📖 Spoke Workloads](docs/spoke_workloads.md)** | Adding application workloads |
| **[🔧 Operations](docs/operations.md)** | Day-2 operations guide |
| **[❗ Troubleshooting](docs/troubleshooting.md)** | Common issues and solutions |

## Architecture

### Core Components

The landing zone implements a **security-first, three-layer architecture**:

- **🏛️ Core Governance**: Management groups, policies, and compliance framework
- **⚙️ Management Layer**: Log Analytics, optional Automation Account, and monitoring
- **🔧 Infrastructure Layer**: Hub-spoke networking with Azure Firewall, VPN Gateway, and Bastion

### Subscription Flexibility

Supports both **single-subscription** (cost-optimized) and **multi-subscription** (enterprise-scale) deployments:

| Component | Single Sub | Multi-Sub | Purpose |
|-----------|------------|-----------|----------|
| Core & Management | ✅ | Management | Governance, monitoring |
| Connectivity | ✅ | Connectivity | Hub networking, firewall |
| Identity | ✅ | Identity | Domain controllers |
| Workloads | ✅ | Workload-specific | Applications, AVD, AIB |

### Advanced VM Capabilities

- **Multiple NICs**: Support for complex networking with multiple network interfaces per VM
- **Multiple Data Disks**: Flexible storage configuration with different performance tiers
- **High Availability**: Availability zones, load balancing, and clustering support
- **Enterprise Storage**: Write Accelerator, customer-managed encryption, and performance optimization
- **Microsoft Naming**: Zero-padded naming following official Azure conventions (nic01, datadisk01)

### Optional Components

- **Identity Services**: Active Directory domain controllers with multiple NICs, advanced backup policies, and high availability
- **Azure Virtual Desktop**: Complete AVD deployment with host pools, scaling plans, FSLogix storage, and custom images
- **Azure Image Builder**: Custom VM images with PowerShell DSC optimizations and private endpoint security
- **Spoke Workloads**: Multi-tier applications with advanced VM configurations supporting multiple NICs and data disks
- **Governance Policies**: Automated tag inheritance and backup audit policies for compliance

## Security & Compliance

**Security-first design** with Zero Trust architecture:

- **🔐 Zero Trust**: Default deny, private endpoints, network isolation
- **🛡️ Enhanced Security**: Trusted Launch VMs, disk encryption, Microsoft Defender
- **📋 Compliance**: Well-Architected Framework alignment, automated policies
- **🔄 Backup & Recovery**: Automated VM backup with Azure Recovery Services Vault

**Built-in Policies**:

- Deploy Azure Monitor Agent with data collection rules
- Audit backup protection for VMs and Azure Files
- Automated tag inheritance (Environment, Owner, CostCenter, Workload)
- Require private endpoints for storage and services
- Enable disk encryption and Trusted Launch VMs
- Deploy Microsoft Defender for Cloud

## Prerequisites

- **[Terraform](https://www.terraform.io/downloads.html)** >= 1.9
- **[Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)** >= 2.61
- Azure subscriptions with Owner/Contributor permissions
- PowerShell or Bash terminal

## Module Versions

| Component | Version | Status |
|-----------|---------|--------|
| Terraform | >= 1.9 | ✅ |
| AzureRM Provider | ~> 4.0 | ✅ |
| ALZ Core (avm-ptn-alz) | ~> 0.13.0 | ✅ |
| ALZ Management | ~> 0.9.0 | ✅ |
| ALZ Connectivity Hub-Spoke | ~> 0.11.3 | ✅ |
| AVD Management Plane | ~> 0.3.2 | ✅ |
| AVM Storage Account | ~> 0.2.7 | ✅ |
| AVM Compute Gallery | ~> 0.1.2 | ✅ |

## Environment Examples

### Basic Configuration

```hcl
# environments/my-deployment.tfvars
org_name    = "myorg"
environment = "prod"
location    = "UK South"

# Subscription IDs
management_subscription_id   = "your-subscription-id"
connectivity_subscription_id = "your-subscription-id"

# Enable core components
core_config = {
  enabled = true
}

management_config = {
  enabled = true
}

# Optional: Control automation account deployment (default: true)
enable_automation_account = false

connectivity_config = {
  enabled = true
  hub_virtual_network = {
    address_space = ["10.0.0.0/16"]
  }
  firewall = {
    enabled = true
  }
}
```

### Advanced VM Configuration Example

```hcl
# Multi-tier application with multiple NICs and disks
virtual_machines = {
  "web-server" = {
    count              = 2
    vm_size            = "Standard_D4s_v5"
    availability_zones = ["1", "2"]
    vm_name_prefix     = "WEB"
    
    # Multiple network interfaces
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
    
    # Multiple data disks with different performance
    data_disks = [
      {
        size_gb                   = 512
        storage_account_type      = "Premium_LRS"
        lun                       = 0
        write_accelerator_enabled = false
      },
      {
        size_gb                   = 1024
        storage_account_type      = "Premium_LRS"
        caching                   = "None"
        lun                       = 1
        write_accelerator_enabled = true  # High IOPS database disk
      }
    ]
  }
}

# Expected names: WEB01, WEB02
# NICs: WEB01-nic01, WEB01-nic02 
# Disks: WEB01-datadisk01, WEB01-datadisk02
```

### Advanced Configuration

See **[Configuration Guide](docs/configuration.md)** for detailed examples including:

- Identity services with domain controllers
- Azure Virtual Desktop deployment
- Azure Image Builder setup
- Multi-subscription architecture
- Custom security policies
- Automation account deployment control via `enable_automation_account`

## Common Deployment Scenarios

### 1. Foundation Only (Quickest Start)

```bash
terraform apply -var-file="environments/prod.tfvars"
```

Deploys core governance, management, and hub networking without VMs.

### 2. With Identity Services

Enable `identity_config` to add domain controllers for hybrid environments.

### 3. With Azure Virtual Desktop

Enable `avd_config` for virtual desktop infrastructure.

### 4. Custom Image Pipeline

Enable `aib_config` for Azure Image Builder with custom VM images.

### 5. Complete Enterprise

Enable all components for full-featured enterprise landing zone.

## Terraform Commands

```bash
# Initialize and validate
terraform init
terraform fmt -recursive .
terraform validate

# Plan and apply
terraform plan -var-file="environments/my-deployment.tfvars -out="environments/my-deployment.tfplan""
terraform apply -var-file="environments/my-deployment.tfvars"

# Clean up (when needed)
terraform destroy -var-file="environments/my-deployment.tfvars"
```

## Remote Backend Setup

For team collaboration, configure remote state storage:

```bash
# Run the setup script to create backend storage
./setup-backend.sh

# Update terraform.tf backend configuration
# See setup-backend.sh output for exact values
```

See **[Backend Setup Guide](setup-backend.sh)** for detailed instructions.

## 🛡️ Governance Policies & Compliance

The Azure Landing Zone automatically deploys **80+ Azure policies** following Microsoft's Azure Landing Zone (ALZ) patterns for comprehensive governance, security, and compliance.

### 📋 **Default Policy Assignments**

**✅ AUTOMATICALLY DEPLOYED** - The following policies are deployed during initial terraform apply:

#### **Root Level Policies** (13 policies)

- `Audit-ResourceRGLocation` - Audit resource group locations
- `Audit-TrustedLaunch` - Audit VMs without Trusted Launch
- `Audit-UnusedResourcesCostOptimization` - Audit unused resources
- `Deny-Classic-Resources` - Block classic Azure resources
- `Deny-HybridNetworking` - Block hybrid networking in incorrect scopes
- `Deploy-AzActivity-Log` - Deploy activity log diagnostic settings
- `Deploy-ASC-Monitoring` - Deploy Azure Security Center monitoring
- `Deploy-MDFC-Config` - Deploy Microsoft Defender for Cloud configuration
- `Deploy-Diag-LogsCat` - Deploy diagnostic settings for logs
- `Deploy-vmArc-ChangeTrack` - Deploy change tracking for Arc VMs
- `Deploy-vmHybr-Monitoring` - Deploy monitoring for hybrid VMs
- `Enable-DDoS-VNET` - Enable DDoS protection (disabled by default)
- `Enforce-ALZ-Decomm` - Enforce decommissioned resource policies
- `Enforce-ALZ-Sandbox` - Enforce sandbox resource policies

#### **Platform Level Policies** (25 policies)

- VM monitoring and change tracking policies
- Azure Monitor Agent (AMA) deployment policies  
- Update management and Azure Site Recovery enforcement
- Guest configuration policies for all Azure resource types
- Key Vault, Storage, Network security enforcement policies

#### **Landing Zone Policies** (40+ policies)

- Application security policies (WAF, HTTPS enforcement)
- Network security (NSG requirements, IP forwarding restrictions)
- SQL security (TDE, auditing, threat detection)
- AKS security policies
- Resource-specific governance policies for all Azure services

#### **Connectivity & Identity Policies** (5 policies)

- Network security and access control policies
- Public IP and management port restrictions

### ⚠️ **Manual Post-Deployment Configuration Required**

**Several policies require manual configuration after initial deployment due to AVM dependency limitations:**

#### **🔧 1. Log Analytics Workspace Integration**

**Policies requiring Log Analytics workspace ID:**

- `Deploy-AzActivity-Log`
- `Deploy-Diag-LogsCat`
- `Deploy-VM-Monitoring`
- `Deploy-VMSS-Monitoring`
- `Deploy-vmArc-ChangeTrack`
- `Deploy-vmHybr-Monitoring`

**Manual Configuration Steps:**

```bash
# 1. After first deployment, get the Log Analytics workspace ID
terraform output management

# 2. Add to your tfvars file:
core_config = {
  enabled = true
  policy_default_values = {
    log_analytics_workspace_id = "/subscriptions/xxx/resourceGroups/rg-management/providers/Microsoft.OperationalInsights/workspaces/law-management"
  }
}

# 3. Re-run terraform apply
terraform apply -var-file="environments/your-environment.tfvars"
```

#### **🔧 2. Azure Monitor Agent (AMA) Configuration**

**Policies requiring AMA resources:**

- `Deploy-MDFC-DefSQL-AMA`
- `Deploy-VM-ChangeTrack`
- `Deploy-VMSS-ChangeTrack`

**Manual Configuration Steps:**

- Create data collection rules for change tracking
- Create user-assigned managed identity for AMA
- Update policy parameters with resource IDs

#### **🔧 3. Backup Policy Configuration**

**Backup-related policies:**

- VM backup audit policies (custom)
- File share backup policies (custom)

**Manual Configuration Steps:**

- Configure backup policies in spoke modules
- Set up Recovery Services Vault integration

### 🚀 **Future Automation Plans**

> **📋 Roadmap Note**: We plan to automate the manual configuration steps above by moving Log Analytics workspace ID and AMA resource references directly into the Terraform code. Currently, this is limited by:
>
> - **AVM Dependency Issues**: The Azure Verified Module (AVM) for ALZ has limited support for dynamic policy parameter injection
> - **Terraform Dependencies**: Log Analytics workspace ID is not known until the first apply, causing for_each dependency conflicts
>
> These limitations will be addressed as the AVM ALZ module matures and supports better dependency management.

### 📋 **Implementation Steps**

#### **Phase 1: Initial Deployment**

1. **Deploy Core Infrastructure**: Run `terraform apply` with basic configuration
2. **Verify Policy Deployment**: Check Azure Policy dashboard for deployed policies
3. **Review Compliance**: Initial policies will show compliance status

#### **Phase 2: Manual Configuration**

1. **Configure Log Analytics Integration**: Add workspace ID to policy parameters
2. **Set Up AMA Resources**: Deploy data collection rules and managed identities
3. **Configure Custom Policy Parameters**: Set policy default values for Log Analytics workspace integration
4. **Run Remediation**: Execute policy remediation tasks for existing resources

#### **Phase 3: Monitoring & Compliance**

1. **Set Up Compliance Monitoring**: Configure Azure Policy compliance dashboards
2. **Create Compliance Reports**: Set up automated compliance reporting
3. **Policy Exemptions**: Configure exemptions for legitimate exceptions
4. **Continuous Improvement**: Review and update policies based on compliance results

### 🏷️ **Built-in Governance Features**

All governance policies are automatically deployed through the core ALZ module and include comprehensive coverage for:

- Resource security and compliance
- Monitoring and diagnostic settings
- Network security controls
- Backup and recovery governance
- Cost optimization policies

### 📖 **Related Documentation**

- [Azure Policy Best Practices](https://docs.microsoft.com/azure/governance/policy/)
- [ALZ Policy Reference](https://docs.microsoft.com/azure/cloud-adoption-framework/ready/enterprise-scale/architecture)
- **[🏛️ Custom Architecture](docs/custom_architecture.md)** - Management group policy assignment
- **[🔐 Security](docs/security.md)** - Security policy recommendations
- **[🛡️ Backup Policies](docs/backup-policies.md)** - Backup governance and audit policies

> **💡 Pro Tip**: Use Azure Policy's compliance dashboard to monitor policy adherence across your entire Azure Landing Zone. The built-in policies provide comprehensive governance coverage for security, compliance, and operational best practices.

## Contributing

This implementation follows Microsoft's recommended patterns and AVM standards:

1. Follow AVM naming conventions
2. Ensure WAF alignment  
3. Include appropriate security controls
4. Update documentation

## Support & Resources

- **[Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)** - Official AVM documentation
- **[Azure Landing Zones](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/)** - Microsoft ALZ guidance
- **[Well-Architected Framework](https://learn.microsoft.com/en-us/azure/well-architected/)** - Azure WAF principles
- **[Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)** - Provider 4.x documentation
