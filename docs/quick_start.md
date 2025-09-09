# Quick Start Guide

This guide gets you up and running with the Azure Landing Zone in under 30 minutes, including optional advanced VM configurations with multiple NICs and data disks.

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed and configured
- [Terraform](https://www.terraform.io/downloads.html) >= 1.9 installed
- Azure subscriptions with appropriate permissions
- PowerShell or Bash terminal

## 1. Initial Setup

```bash
# Clone the repository
git clone <repository-url>
cd azure-landing-zone

# Login to Azure
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Register required Azure providers
az provider register -n Microsoft.VirtualMachineImages
az provider register -n Microsoft.Compute
az provider register -n Microsoft.KeyVault
az provider register -n Microsoft.Storage
az provider register -n Microsoft.Network
az provider register -n Microsoft.ContainerInstance
az provider register --namespace Microsoft.DesktopVirtualization
```

## 2. Configure Variables

Copy and customize the example configuration:

```bash
cp environments/prod.tfvars environments/my-deployment.tfvars
```

Edit `environments/my-deployment.tfvars` with your values:

```hcl
# Basic Configuration
org_name    = "myorg"
environment = "prod"
location    = "UK South"

# Subscription IDs
management_subscription_id   = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
connectivity_subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
identity_subscription_id     = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # Optional
infra_subscription_id        = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # Optional

# Enable desired components
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
  firewall = {
    enabled = true
    sku = {
      name = "AZFW_VNet"
      tier = "Standard"
    }
  }
}

# Optional: Identity Services with Domain Controllers
identity_config = {
  enabled                   = true
  
  virtual_network = {
    name          = "vnet-identity-prod-uks"
    address_space = ["10.1.0.0/16"]
    subnets = {
      "snet-domain-controllers" = {
        address_prefixes = ["10.1.1.0/24"]
      }
    }
  }
  
  # Advanced VM configuration with multiple NICs and disks
  deploy_virtual_machines = true
  virtual_machines = {
    "dc" = {
      count              = 2
      vm_size            = "Standard_D2s_v5"
      os_type            = "Windows"
      os_sku             = "2022-datacenter"
      availability_zones = ["1", "2"]
      vm_name_prefix     = "DC"
      
      # Single NIC for domain controllers
      network_interfaces = [
        {
          subnet_name                   = "snet-domain-controllers"
          private_ip_allocation_method  = "Static"
          enable_accelerated_networking = false
        }
      ]
      
      # Data disk for AD DS (caching disabled)
      data_disks = [
        {
          size_gb              = 256
          caching              = "None"     # Critical for AD DS
          storage_account_type = "Premium_LRS"
          lun                  = 0
        }
      ]
    }
  }
}

# Optional: Infrastructure spoke with multi-tier application
infra_config = {
  virtual_network = {
    name          = "vnet-infra-prod-uks"
    address_space = ["10.2.0.0/16"]
    subnets = {
      "snet-web"  = { address_prefixes = ["10.2.1.0/24"] }
      "snet-app"  = { address_prefixes = ["10.2.2.0/24"] }
      "snet-data" = { address_prefixes = ["10.2.3.0/24"] }
    }
  }
  
  # Example: Web servers with dual NICs
  deploy_virtual_machines = true
  virtual_machines = {
    "web" = {
      count              = 2
      vm_size            = "Standard_D4s_v5"
      availability_zones = ["1", "2"]
      vm_name_prefix     = "WEB"
      
      # Multiple NICs for network segmentation
      network_interfaces = [
        {
          subnet_name                   = "snet-web"   # Primary web network
          enable_accelerated_networking = true
          private_ip_allocation_method  = "Static"
        },
        {
          subnet_name                   = "snet-app"   # Backend communication
          enable_accelerated_networking = true
          private_ip_allocation_method  = "Dynamic"
        }
      ]
      
      # Multiple data disks for different purposes
      data_disks = [
        {
          size_gb              = 512     # Web content
          storage_account_type = "Premium_LRS"
          lun                  = 0
        },
        {
          size_gb              = 256     # Logs
          storage_account_type = "StandardSSD_LRS"
          lun                  = 1
        }
      ]
    }
  }
}
```

## 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var-file="environments/my-deployment.tfvars"

# Deploy (takes 15-30 minutes)
terraform apply -var-file="environments/my-deployment.tfvars"
```

## 4. Verify Deployment

Check the Azure portal for:

- ✅ Management groups and policies in the ALZ structure
- ✅ Log Analytics workspace and monitoring infrastructure with data collection rules (Automation Account optional)
- ✅ Hub virtual network with Azure Firewall and Bastion
- ✅ Identity spoke with domain controllers (if enabled)
- ✅ Infrastructure spoke with multi-tier VMs (if enabled)
- ✅ Proper VM naming: DC01, DC02, WEB01, WEB02 (following Microsoft conventions)
- ✅ Multiple NICs: WEB01-nic01, WEB01-nic02
- ✅ Multiple disks: WEB01-datadisk01, WEB01-datadisk02

## Configuration Examples

### Basic Foundation (Minimal)

```bash
# Deploy only core governance and hub networking
terraform apply -var-file="environments/foundation-only.tfvars"
```

### With Identity Services

```bash
# Add domain controllers to the deployment
terraform apply -var-file="environments/with-identity.tfvars"
```

### Advanced Multi-NIC VMs

```bash
# Deploy with complex VM configurations
terraform apply -var-file="environments/advanced-vms.tfvars"
```

### Resource Naming Examples

The module follows Microsoft naming conventions with zero-padded numbers:

**Domain Controllers:**

- VMs: `DC01`, `DC02`
- NICs: `DC01-nic01`, `DC02-nic01`
- Data Disks: `DC01-datadisk01`, `DC02-datadisk01`
- OS Disks: `DC01-osdisk`, `DC02-osdisk`

**Web Servers (with dual NICs):**

- VMs: `WEB01`, `WEB02`
- NICs: `WEB01-nic01` (web tier), `WEB01-nic02` (app tier)
- Data Disks: `WEB01-datadisk01` (content), `WEB01-datadisk02` (logs)
- OS Disks: `WEB01-osdisk`, `WEB02-osdisk`

## Next Steps

- [Configure backend storage](../setup-backend.sh) for team collaboration
- [Customize configurations](CONFIGURATION.md) for advanced VM scenarios
- [Add spoke workloads](SPOKE_WORKLOADS.md) with complex networking
- [Review security settings](SECURITY.md) and compliance
- [Explore examples](../examples/) for specific scenarios

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.