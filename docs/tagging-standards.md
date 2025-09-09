# 🏷️ Azure Landing Zone - Tagging Standards

## Overview

This document defines the comprehensive tagging strategy for the Azure Landing Zone implementation, ensuring consistent resource identification, governance, and cost management across all Azure subscriptions and resources.

## Required Tags

### Core Governance Tags (Required on ALL resources)

| Tag Name | Purpose | Example Values | Validation |
|----------|---------|----------------|------------|
| `Environment` | Environment classification | Production, Development, Test, Staging, Demo | ✅ Enforced |
| `Workload` | ALZ workload classification | Management, Connectivity, Identity, Infrastructure | ✅ ALZ Policy |
| `Owner` | Resource ownership/responsibility | IT, Development Team, Finance | ✅ Enforced |
| `CostCenter` | Financial allocation/billing | Shared, HR, Finance, Marketing | ✅ Enforced |

## Tag Flow

**prod.tfvars** → **main.tf** → **submodules**

```hcl
# prod.tfvars defines base tags
default_tags = {
  Environment = "Production" 
  Owner       = "IT"
  CostCenter  = "Shared"
}

# Each module adds Workload
tags = merge(var.default_tags, {
  Workload = "Management"  # Module-specific
})
```

## Workload Classification

### Hub Services

- **Management**: Log Analytics, Automation, Backup, Monitoring
- **Connectivity**: Firewall, VPN, Bastion, Hub networking
- **Azure Image Builder**: Custom image creation and management

### Spoke Services

- **Identity**: Domain controllers, identity infrastructure
- **Infrastructure**: Application servers, databases, storage
- **Azure Virtual Desktop**: AVD host pools, workspaces, session hosts

## Workload Values by Module

### Management Module

- **Workload**: "Management"
- **Resources**: Log Analytics workspaces, Automation accounts, Recovery Services vaults, Managed identities

### Connectivity Module

- **Workload**: "Connectivity"
- **Resources**: Azure Firewall, VPN Gateways, Bastion hosts, Virtual networks, Network security groups

### Spoke Modules

- **Identity Spoke**: "Identity" - Domain controllers, identity infrastructure
- **Infrastructure Spoke**: "Infrastructure" - Application servers, databases, storage

### AVD Module

- **Workload**: "Azure Virtual Desktop" 
- **Resources**: Host pools, workspaces, application groups, session hosts

### AIB Module

- **Workload**: "Azure Image Builder"
- **Resources**: Image templates, compute galleries, managed identities

### Core Module

- **Workload**: "Management" (inherited from ALZ governance)
- **Resources**: Management groups, policy assignments

### Root Resources

- **Workload**: "Telemetry"
- **Resources**: Telemetry tracking resources

## Tag Implementation Patterns

### Standard Pattern (Most Resources)

```hcl
tags = merge(var.default_tags, {
  Workload = "Management"
  Service         = "LogAnalytics"
})
```

### Centralized Pattern (Using Locals)

```hcl
# In naming.tf
locals {
  management_tags = merge(var.default_tags, {
    Workload = "Management"
  })
}

# In resource definitions
tags = local.management_tags
```

### Service-Specific Pattern

```hcl
tags = merge(local.spoke_tags, {
  Service = "VirtualMachine"
  Role    = "DomainController"  # Additional context
})
```

## Validation Rules

### Environment Values

- Must be one of: Production, Development, Test, Staging, Demo
- Case-sensitive (PascalCase required)

### Owner Format

- Must start with uppercase letter
- Can contain letters, numbers, spaces, hyphens, underscores
- Examples: "IT", "Development Team", "Finance-Operations"

### Tag Key Naming

- Use PascalCase (e.g., Workload, not service_workload)
- No special characters except hyphens and underscores
- Maximum 128 characters

### Tag Value Limits

- Maximum 256 characters per value
- No leading/trailing whitespace
- Consistent casing within same tag across resources

## Cost Allocation Strategy

### CostCenter Mapping

```hcl
# Production cost allocation
CostCenter = "Shared"     # Hub infrastructure costs
CostCenter = "IT"         # IT-managed workloads
CostCenter = "Finance"    # Finance department workloads
CostCenter = "HR"         # Human resources workloads
```

### Environment-Based Allocation

- **Production**: Full cost allocation to business units
- **Development/Test**: Shared development costs
- **Demo**: Marketing/sales allocation

## ALZ Policy Integration

### Required by ALZ Governance

- `Environment` - Used by conditional policies
- `Workload` - Used for archetype-specific policies

### Policy Assignment Scope

- Root Management Group: Base governance policies
- Platform Management Groups: Platform-specific policies  
- Landing Zone Management Groups: Workload-specific policies

## Compliance and Auditing

### Tag Inheritance

- Resource groups → Resources (automatic)
- Subscription → Resource groups (policy-enforced)
- Management group → Subscriptions (policy-enforced)

### Audit Queries

```kql
// Find resources missing required tags
Resources
| where tags !has "Environment" or tags !has "Owner" or tags !has "CostCenter"
| project name, type, resourceGroup, subscriptionId, tags

// Cost analysis by service workload
Resources
| extend Workload = tags["Workload"]
| summarize ResourceCount = count() by Workload, type
```

## Module-Specific Implementation

### Core Module

```hcl
tags = merge(var.default_tags, {
  Workload = "Management"
})
```

### Management Module

```hcl
management_tags = merge(var.default_tags, {
  Workload = "Management"
})
```

### Connectivity Module

```hcl
connectivity_tags = merge(var.default_tags, {
  Workload = "Connectivity"
})

# Service-specific resources
tags = merge(local.connectivity_tags, {
  Service = "Firewall"
})
```

### Spoke Modules

```hcl
spoke_tags = merge(var.default_tags, {
  Workload = var.workload_role  # "Identity" or "Infrastructure"
})
```

### AVD Module

```hcl
avd_tags = merge(var.default_tags, {
  Workload = "Azure Virtual Desktop"
})
```

### AIB Module

```hcl
tags = merge(var.default_tags, {
  Workload = "Azure Image Builder"
  Service         = "ComputeGallery"
})
```

## Best Practices

### Do's ✅

- Always use `merge(var.default_tags, {...})` pattern
- Apply consistent PascalCase naming
- Include Workload for ALZ compliance
- Use descriptive Service tags for resource identification
- Validate tag requirements in variable definitions

### Don'ts ❌

- Never use `tags = var.default_tags` directly (loses service context)
- Don't hardcode environment-specific values in modules
- Avoid special characters in tag keys
- Don't exceed Azure tag limits (50 tags per resource)
- Never omit required governance tags

## Migration Guide

### Existing Resources

1. Run compliance scan to identify missing tags
2. Use Azure Policy remediation for bulk updates
3. Update Terraform configurations for consistency
4. Validate against new tagging standards

### New Deployments

1. Use updated variable validation rules
2. Follow module-specific tagging patterns
3. Test tag inheritance in non-production first
4. Monitor compliance through Azure Policy

## Troubleshooting

### Common Issues

- **Validation Errors**: Check required tags are present in default_tags
- **ALZ Policy Conflicts**: Ensure Workload matches archetype
- **Tag Inheritance**: Verify resource group tags propagate correctly
- **Cost Allocation**: Confirm CostCenter values match billing requirements

### Verification Commands

```bash
# Terraform validation
terraform validate

# Check tag compliance
az policy state list --filter "PolicyDefinitionName eq 'RequiredTags'"

# Review resource tags
az resource list --query "[].{Name:name, Tags:tags}" --output table
```
