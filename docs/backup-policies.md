# Azure Landing Zone - Backup Policies

This document outlines the backup policies configured in the Azure Landing Zone and the requirements for protecting VMs and Azure Files.

## Overview

The Azure Landing Zone includes Recovery Services Vaults in both Identity and Infrastructure spokes with pre-configured backup policies. These policies provide flexible protection tiers with staggered backup schedules to optimize performance and resource utilization.

> **⚠️ Backup Policy Implementation**: The landing zone deploys audit policies to monitor backup compliance rather than automated deployment policies. Due to Azure Verified Modules (AVM) library inheritance behavior, the complex "Deploy-VM-Backup" policy from the ALZ library cannot be fully unassigned and remains disabled but visible in policy assignments. Backup protection must be configured through spoke module settings (`enable_backup = true`) or manual assignment to the policies defined below. See [AVM Issue #255](https://github.com/Azure/terraform-azurerm-avm-ptn-alz/issues/255) for technical details.

## Virtual Machine Backup Policies

### 1. Basic Policy (`vm_basic_14day`)

**Policy Name**: `VM-Basic-14Day-Daily-Policy`

- **Purpose**: Cost-optimized protection for non-critical workloads
- **Schedule**: Daily backup at 01:00 GMT Standard Time (off-peak hours)
- **Retention**: 14 days daily retention
- **Instant Recovery**: 5 days (shorter instant recovery for cost optimization)
- **Backup Resource Group**: `rg-backup-{environment}-{location}-servers`
- **Use Cases**:
  - Development environments
  - Test servers
  - Non-critical applications
  - Proof-of-concept workloads
  - Cost-sensitive deployments

### 2. Standard Policy (`vm_standard_30day`)

**Policy Name**: `VM-Standard-30Day-Daily-Policy`

- **Purpose**: Standard protection for most production workloads
- **Schedule**: Daily backup at 23:00 GMT Standard Time
- **Retention**: 30 days daily retention
- **Instant Recovery**: 7 days (allows quick restore from snapshots)
- **Backup Resource Group**: `rg-backup-{environment}-{location}-servers`
- **Use Cases**:
  - Web servers
  - Application servers
  - Standard production workloads
  - Business applications with moderate criticality

### 3. Enhanced Policy (`vm_enhanced_90day`)

**Policy Name**: `VM-Enhanced-90Day-Weekly-Policy`

- **Purpose**: Enhanced protection for important workloads requiring longer retention
- **Schedule**: Daily backup at 22:30 GMT Standard Time
- **Retention Strategy**:
  - **Daily**: 30 days
  - **Weekly**: 12 weeks (retained on Saturdays)
- **Instant Recovery**: 7 days (allows quick restore from snapshots)
- **Backup Resource Group**: `rg-backup-{environment}-{location}-servers`
- **Use Cases**:
  - Important application servers
  - Business-critical workloads
  - Systems requiring quarterly retention
  - Mid-tier production environments

### 4. Extended Policy (`vm_extended_7year`)

**Policy Name**: `VM-Extended-7Year-Lifecycle-Policy`

- **Purpose**: Long-term protection for critical workloads requiring compliance retention
- **Schedule**: Daily backup at 22:00 GMT Standard Time (priority scheduling)
- **Retention Strategy**:
  - **Daily**: 30 days
  - **Weekly**: 12 weeks (retained on Saturdays)
  - **Monthly**: 12 months (1st day of each month)
  - **Yearly**: 7 years (December 1st)
- **Instant Recovery**: 7 days (allows quick restore from snapshots)
- **Backup Resource Group**: `rg-backup-{environment}-{location}-servers`
- **Use Cases**:
  - Database servers (SQL Server, Oracle, etc.)
  - Domain controllers
  - Financial systems
  - Compliance-driven workloads
  - Critical business data requiring long-term retention

## Azure Files Backup Policies

### 1. Files Standard Policy (`files_standard_30day`)

**Policy Name**: `Files-Standard-30Day-Daily-Policy`

- **Purpose**: Standard protection for most Azure File Shares
- **Schedule**: Daily backup at 21:00 GMT Standard Time
- **Retention**: 30 days daily retention
- **Recommended For**:
  - General file shares
  - User data storage
  - Application file shares
  - Standard business documents

### 2. Files Enhanced Policy (`files_enhanced_90day`)

**Policy Name**: `Files-Enhanced-90Day-Daily-Policy`

- **Purpose**: Enhanced protection for important Azure File Shares requiring longer retention
- **Schedule**: Daily backup at 20:00 GMT Standard Time (priority time)
- **Retention**: 90 days daily retention
- **Recommended For**:
  - FSLogix profile containers
  - Critical shared storage
  - Compliance-driven file shares
  - Business-critical documents

## Policy Configuration Details

### Recovery Services Vault Configuration

Each spoke (Identity and Infrastructure) includes:

```hcl
# VM Backup Policies - 4-tier approach
vm_backup_policy = {
  vm_basic_14day = {
    name                           = "VM-Basic-14Day-Daily-Policy"
    timezone                       = "GMT Standard Time"
    policy_type                    = "V2"
    frequency                      = "Daily"
    instant_restore_retention_days = 5
    
    backup = { time = "01:00" }
    retention_daily = 14
  }
  
  vm_standard_30day = {
    name                           = "VM-Standard-30Day-Daily-Policy"
    timezone                       = "GMT Standard Time"
    policy_type                    = "V2"
    frequency                      = "Daily"
    instant_restore_retention_days = 7
    
    backup = { time = "23:00" }
    retention_daily = 30
  }
  
  vm_enhanced_90day = {
    name                           = "VM-Enhanced-90Day-Weekly-Policy"
    timezone                       = "GMT Standard Time"
    policy_type                    = "V2"
    frequency                      = "Daily"
    instant_restore_retention_days = 7
    
    backup = { time = "22:30" }
    retention_daily = 30
    retention_weekly = {
      count    = 12
      weekdays = ["Saturday"]
    }
  }
  
  vm_extended_7year = {
    name                           = "VM-Extended-7Year-Lifecycle-Policy"
    timezone                       = "GMT Standard Time"
    policy_type                    = "V2"
    frequency                      = "Daily"
    instant_restore_retention_days = 7
    
    backup = { time = "22:00" }
    retention_daily = 30
    retention_weekly = {
      count    = 12
      weekdays = ["Saturday"]
    }
    retention_monthly = {
      count = 12
      days  = [1]
      include_last_days = false
    }
    retention_yearly = {
      count  = 7
      months = ["December"]
      days   = [1]
      include_last_days = false
    }
  }
}

# File Share Backup Policies - 2-tier approach
file_share_backup_policy = {
  files_standard_30day = {
    name      = "Files-Standard-30Day-Daily-Policy"
    timezone  = "GMT Standard Time"
    frequency = "Daily"
    
    backup = { time = "21:00" }
    retention_daily = 30
  }
  
  files_enhanced_90day = {
    name      = "Files-Enhanced-90Day-Daily-Policy"
    timezone  = "GMT Standard Time"
    frequency = "Daily"
    
    backup = { time = "20:00" }
    retention_daily = 90
  }
}
```

### Backup Schedule Coordination

The backup schedules are staggered across time zones to distribute load and optimize performance:

1. **01:00** - VM Basic policy (off-peak hours for non-critical workloads)
2. **20:00** - Files Enhanced policy (priority time for important file shares)
3. **21:00** - Files Standard policy (standard file share backup)
4. **22:00** - VM Extended policy (priority time for critical VMs)
5. **22:30** - VM Enhanced policy (important VM backup)
6. **23:00** - VM Standard policy (main production window)

## Resource Protection Requirements

### ⚠️ IMPORTANT: Azure Policy Required

**The backup policies created above are templates only. Virtual Machines and Azure Files must be assigned to these policies through Azure Policy automation.**

### Virtual Machine Protection

#### Manual Assignment (Not Recommended)

VMs can be manually assigned to backup policies through:

- Azure Portal → Recovery Services Vault → Backup
- PowerShell/CLI scripts
- Terraform `backup_protected_vm` configuration

#### Recommended: Azure Policy Automation

Deploy Azure Policy initiatives to automatically:

- Discover VMs based on tags, resource groups, or naming conventions
- Assign appropriate backup policies based on workload classification
- Ensure compliance across all subscriptions

**Example Policy Scenarios**:

```yaml
# Critical Production VMs → Extended Policy
Tag: Environment = "Production"
Tag: BackupTier = "Critical|Extended|LongTerm"
→ Assign: VM-Extended-7Year-Lifecycle-Policy

# Important Production VMs → Enhanced Policy
Tag: Environment = "Production"
Tag: BackupTier = "Enhanced|Important"
→ Assign: VM-Enhanced-90Day-Weekly-Policy

# Standard Production VMs → Standard Policy  
Tag: Environment = "Production"
Tag: BackupTier = "Standard|Production"
→ Assign: VM-Standard-30Day-Daily-Policy

# Development/Test VMs → Basic Policy
Tag: Environment = "Development|Test|Staging"
Tag: BackupTier = "Basic|NonCritical"
→ Assign: VM-Basic-14Day-Daily-Policy

# Important File Shares → Enhanced Files Policy
Tag: FileShareTier = "Enhanced|Critical|FSLogix"
→ Assign: Files-Enhanced-90Day-Daily-Policy

# Standard File Shares → Standard Files Policy
Tag: FileShareTier = "Standard|General"
→ Assign: Files-Standard-30Day-Daily-Policy
```

### Azure Files Protection

#### Manual Assignment (Not Recommended)

File shares can be manually protected by:

- Configuring `backup_protected_file_share` in Terraform
- Using Azure Portal backup configuration
- PowerShell/CLI automation

#### Recommended: Azure Policy Automation

Deploy policies to automatically:

- Discover Azure Storage Accounts with File Shares
- Enable backup based on storage account tags or naming
- Assign to appropriate file share backup policies

**Example Configuration**:

```hcl
# Terraform example for manual protection
backup_protected_file_share = {
  "fslogix-profiles" = {
    source_storage_account_id     = "/subscriptions/.../storageAccounts/stfslogix001"
    backup_file_share_policy_name = "Files-Enhanced-90Day-Daily-Policy"  # For critical FSLogix profiles
    source_file_share_name        = "profiles"
  }
  "general-data" = {
    source_storage_account_id     = "/subscriptions/.../storageAccounts/stgeneral001"
    backup_file_share_policy_name = "Files-Standard-30Day-Daily-Policy"  # For general file shares
    source_file_share_name        = "data"
  }
}
```

## Backup Cost Optimization

### Policy Selection Guidelines

| Workload Type | Recommended Policy | Justification |
|---------------|-------------------|---------------|
| Domain Controllers | VM Extended 7-Year | Critical AD infrastructure requires long-term compliance retention |
| Database Servers | VM Extended 7-Year | Critical data requires comprehensive backup lifecycle |
| Financial Systems | VM Extended 7-Year | Compliance requirements demand long-term retention |
| Important App Servers | VM Enhanced 90-Day | Business-critical applications requiring quarterly retention |
| Production Web Servers | VM Standard 30-Day | Standard production workloads with moderate retention needs |
| General App Servers | VM Standard 30-Day | Standard business applications with normal recovery requirements |
| FSLogix File Shares | Files Enhanced 90-Day | User profiles need extended protection, 90-day retention |
| Critical File Shares | Files Enhanced 90-Day | Important shared storage requiring longer retention |
| General File Shares | Files Standard 30-Day | Standard file storage with normal retention needs |
| Development VMs | VM Basic 14-Day | Non-production workloads, cost-optimized |
| Test Environments | VM Basic 14-Day | Temporary workloads, minimal retention needs |
| Sandbox/POC VMs | VM Basic 14-Day | Proof-of-concept systems with short-term needs |

### Storage Optimization

All policies use:

- **Locally Redundant Storage (LRS)** for cost optimization
- **Standard tier** Recovery Services Vaults
- **Instant Recovery Points** limited to 7 days to control costs
- **Staggered backup schedules** to distribute I/O load

## Monitoring and Compliance

### Built-in Monitoring

Recovery Services Vaults include:

- **Log Analytics Integration** for centralized monitoring
- **Azure Monitor Alerts** for backup job failures
- **Diagnostic Settings** for audit logging

### Compliance Reporting

Use Azure Policy compliance reports to:

- Identify unprotected VMs and File Shares
- Monitor backup job success rates
- Track recovery point objectives (RPO) compliance
- Generate audit reports for governance

## Implementation Checklist

### Phase 1: Infrastructure Setup

- [x] Recovery Services Vaults deployed in Identity and Infrastructure spokes
- [x] Backup policies created with appropriate retention settings
- [x] Log Analytics integration configured
- [x] Diagnostic settings enabled

### Phase 2: Policy Automation (Required)

- [ ] Deploy Azure Policy for VM backup assignment
- [ ] Configure Azure Policy for Azure Files protection
- [ ] Test policy automation with pilot resources
- [ ] Validate backup job execution

### Phase 3: Monitoring & Governance

- [ ] Configure backup failure alerts
- [ ] Set up compliance dashboards
- [ ] Establish backup testing procedures
- [ ] Document recovery procedures

## Recovery Procedures

### VM Recovery Options

1. **Instant Recovery** (0-7 days): Fast recovery from local snapshots
2. **Standard Recovery** (8+ days): Recovery from vault storage
3. **Cross-Region Recovery**: Available if enabled in vault configuration

### File Share Recovery Options

1. **Item-level restore**: Restore individual files or folders
2. **Full share restore**: Restore entire file share
3. **Point-in-time recovery**: Restore to specific backup point

## Support and Troubleshooting

### Common Issues

1. **VM Not Appearing for Backup**: Check Azure Policy assignment and VM agent status
2. **Backup Job Failures**: Review diagnostic logs in Log Analytics workspace
3. **Performance Issues**: Verify backup schedules don't conflict with business hours
4. **Cost Overruns**: Review retention policies and instant recovery settings

### Contact Information

- **Infrastructure Team**: For Recovery Services Vault configuration
- **Security Team**: For backup policy compliance and governance  
- **Azure Support**: For platform-specific backup issues

---
