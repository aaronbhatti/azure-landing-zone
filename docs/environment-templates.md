# Environment Templates

This guide explains how to use environment templates for creating consistent, reusable Terraform configurations across different environments.

## Overview

The `environments/templates/` directory contains templates for different environment configurations that can be version-controlled and reused. These templates use placeholder values that are replaced when creating new environments.

## Available Templates

### Production Template (`prod.tfvars.template`)

- Full production configuration with Standard Firewall
- Zone-redundant deployments where supported
- Complete AVD setup with scaling plans
- Enhanced monitoring and backup enabled

### DR Template (`dr.tfvars.template`)

- Disaster Recovery configuration for UK West
- Same IP ranges as production for easy failover
- Identical feature set to production
- Resource naming follows DR conventions

### Test Template (`test.tfvars.template`)

- Comprehensive test configuration with different IP ranges (10.10.x, 10.20.x, etc.)
- Mix of features enabled/disabled to test parameter passing
- Cost-optimized settings (smaller VMs, Basic tiers)
- Extensive customizations for module validation

## Usage Methods

### Method 1: Copy and Rename

```bash
# Navigate to environments directory
cd environments/

# Copy template to create environment file
cp prod.tfvars.template prod.tfvars
cp dr.tfvars.template dr.tfvars
cp test.tfvars.template test.tfvars

# Update subscription IDs and other values
# Edit the .tfvars file and replace "YOUR_SUBSCRIPTION_ID_HERE"
```

### Method 2: Automated Script

```bash
# Create new environment with subscription ID replacement
./environments/new-environment.sh prod staging c7f53b68-70fa-458f-9976-95d722f3312f

# Create without auto-replacement (manual editing needed)
./environments/new-environment.sh test dev
```

### Method 3: Use with Terraform directly

```bash
# Use template file directly (requires setting subscription IDs via environment)
terraform plan -var-file="environments/prod.tfvars.template" \
  -var="management_subscription_id=${TF_VAR_subscription_id}" \
  -var="connectivity_subscription_id=${TF_VAR_subscription_id}"
```

## Template Structure

Each template includes:

- **Basic Configuration**: Organization name, environment, location
- **Subscription IDs**: Placeholder values that need updating
- **Resource Naming**: Environment-specific naming conventions
- **Network Configuration**: IP ranges and connectivity settings
- **Module Configurations**: Identity, Infrastructure, AVD, AIB settings
- **Feature Toggles**: Different combinations for testing

## Customization Steps

Before using any template:

1. **Update Subscription IDs**: Replace `YOUR_SUBSCRIPTION_ID_HERE` with actual subscription IDs
2. **Adjust IP Ranges**: Modify network ranges if needed to avoid conflicts
3. **Customize Resource Names**: Update resource group and resource names as needed
4. **Configure Features**: Enable/disable features based on requirements

## IP Range Guidelines

| Environment | Hub Range | Identity Range | Infrastructure Range | AVD Range |
|------------|-----------|----------------|-------------------|-----------|
| Production | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 | 10.3.0.0/16 |
| DR | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 | 10.3.0.0/16 |
| Test | 10.10.0.0/16 | 10.20.0.0/16 | 10.30.0.0/16 | 10.40.0.0/16 |

## Automation Script Usage

The `new-environment.sh` script automates environment creation:

```bash
# Syntax
./environments/new-environment.sh <template> <environment_name> [subscription_id]

# Examples
./environments/new-environment.sh prod staging c7f53b68-70fa-458f-9976-95d722f3312f
./environments/new-environment.sh test dev
./environments/new-environment.sh dr disaster-recovery
```

### Script Features

- Validates template exists before proceeding
- Warns if target file already exists
- Automatically replaces subscription ID placeholders
- Updates environment names in configuration
- Provides next steps guidance

## Git Integration

Templates are committed to version control and provide:

- **Team Sharing**: Consistent configurations across team members
- **Central Updates**: New features added to templates benefit all environments
- **Change Tracking**: Template modifications are tracked over time
- **Base Configurations**: Starting point for new environments

## Security Considerations

- Templates use `YOUR_SUBSCRIPTION_ID_HERE` placeholders for safe version control
- Never commit actual subscription IDs to templates
- Actual environment files (.tfvars) should be in .gitignore if they contain sensitive data
- Use Azure Key Vault references for secrets rather than hardcoding

## Best Practices

1. **Keep Templates Generic**: Use placeholder values for environment-specific settings
2. **Document Changes**: Update documentation when adding new templates
3. **Test Templates**: Validate templates work before committing changes
4. **Version Control**: Commit template changes separately from environment-specific configs
5. **Consistent Naming**: Follow established naming conventions across templates
6. **Regular Updates**: Keep templates current with latest module features

## Example Workflow

1. **Choose Template**: Select appropriate template (prod, dr, test)
2. **Create Environment**: Use script or manual copy
3. **Customize Configuration**: Update subscription IDs and environment-specific values
4. **Validate**: Run `terraform plan` to check configuration
5. **Deploy**: Apply changes with `terraform apply`
6. **Document**: Update any environment-specific documentation

## Troubleshooting

### Common Issues

**Missing Subscription IDs**

```bash
# Error: subscription_id is required
# Solution: Update all YOUR_SUBSCRIPTION_ID_HERE placeholders
```

**IP Range Conflicts**

```bash
# Error: Address space conflicts with existing network
# Solution: Adjust IP ranges in template before deployment
```

**Permission Issues**

```bash
# Error: Insufficient permissions to create resources
# Solution: Ensure service principal has required RBAC roles
```

For additional help, see [troubleshooting.md](troubleshooting.md).
