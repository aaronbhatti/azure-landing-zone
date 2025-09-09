# Custom Architecture Configuration

This document explains how to use custom management group names and architecture definitions in your Azure Landing Zone deployment.

## Overview

The Azure Landing Zone implementation supports custom management group hierarchies through the ALZ provider's library references feature. This allows you to:

- Define custom management group names (e.g., "CNNECT" instead of default ALZ names)
- Customize the management group hierarchy structure
- Maintain compliance with your organization's naming conventions

## Configuration Components

### 1. ALZ Provider Configuration

The ALZ provider in `terraform.tf` is configured with library references to load custom architecture files:

```hcl
provider "alz" {
  library_references = [
    {
      path = "platform/alz"
      ref  = "2025.02.0"          # Latest ALZ library version
    },
    {
      custom_url = "${path.root}/modules/core/lib"  # Local custom architecture
    }
  ]
}
```

**Key Configuration Points:**

- `ref = "2025.02.0"` - Uses the latest Azure Landing Zone library (update as needed)
- `custom_url` - Points to the directory containing your custom architecture file
- The custom library is loaded **in addition to** the standard ALZ library

### 2. Custom Architecture Definition File

Location: `modules/core/lib/custom.alz_architecture_definition.json`

This file defines your custom management group hierarchy:

```json
{
  "name": "custom",
  "management_groups": [
    {
      "id": "cnnect",
      "display_name": "CNNECT",
      "parent_id": null,
      "archetypes": ["root"],
      "exists": false
    },
    {
      "id": "platform",
      "display_name": "Platform", 
      "parent_id": "cnnect",
      "archetypes": ["platform"],
      "exists": false
    }
    // ... additional management groups
  ],
  "archetypes": {
    // ... archetype definitions
  }
}
```

### 3. Core Module Configuration

The core module in `modules/core/main.tf` references the custom architecture:

```hcl
module "alz" {
  source  = "Azure/avm-ptn-alz/azurerm"
  version = "~> 0.13.0"
  
  architecture_name = "custom"    # Must match the "name" field in JSON file
  # ... other configuration
}
```

## Customizing Management Group Names

### Step 1: Modify the Architecture File

Edit `modules/core/lib/custom.alz_architecture_definition.json` to change management group names:

```json
{
  "name": "custom",
  "management_groups": [
    {
      "id": "your-org-name",           # ← Change this to your organization name
      "display_name": "YOUR ORG NAME", # ← Change this to your display name
      "parent_id": null,
      "archetypes": ["root"],
      "exists": false
    },
    // Update all other management groups as needed
  ]
}
```

### Step 2: Update Required Fields

**Critical Fields to Customize:**

- `id` - The management group identifier (lowercase, no spaces)
- `display_name` - The friendly name shown in Azure Portal
- `parent_id` - Reference to parent management group ID (must match another MG's `id`)

**Field Requirements:**

- `name` - Must be "custom" to match `architecture_name` in core module
- `archetypes` - Array of archetype names (don't change unless you know what you're doing)
- `exists` - Set to `false` for new management groups

### Step 3: Validate the Configuration

1. **Check JSON Syntax:**

   ```bash
   # Validate JSON format
   cat modules/core/lib/custom.alz_architecture_definition.json | jq .
   ```

2. **Test Terraform Plan:**

   ```bash
   terraform plan -var-file="environments/prod.tfvars"
   ```

3. **Verify Management Group Names:**
   Look for your custom names in the plan output:

   ```hcl
   defaultManagementGroup = "/providers/Microsoft.Management/managementGroups/YOUR-ORG-NAME"
   ```

## Management Group Hierarchy Structure

The current hierarchy structure is:

```hcl
YOUR-ORG-NAME (Root)
├── platform
│   ├── connectivity
│   ├── identity  
│   └── management
└── landingzones
    ├── avd
    └── infrastructure
```

### Customizing the Hierarchy

To add/remove management groups:

1. **Add a new management group:**

   ```json
   {
     "id": "security",
     "display_name": "Security",
     "parent_id": "platform",        # Parent must exist
     "archetypes": ["security"],     # Use appropriate archetype
     "exists": false
   }
   ```

2. **Change parent relationships:**
   - Update `parent_id` to move management groups
   - Ensure parent exists in the same file

3. **Remove management groups:**
   - Delete the management group object
   - Update any `parent_id` references that pointed to it

## Integration with Terraform Variables

The custom architecture is integrated with your Terraform configuration:

### Variables Reference

In your `prod.tfvars`:

```hcl
core_config = {
  enabled                       = true
  management_group_display_name = "CNNECT"           # Should match root MG display_name
  management_group_id           = "alz"              # Architecture reference (keep as "alz")
  management_group_parent_id    = "3ec094fc-4da6..." # Tenant ID
}
```

**Important:**

- `management_group_display_name` should match your root management group's `display_name`
- `management_group_id` stays as "alz" - this is the architecture reference, not your custom name
- The actual custom names come from the JSON file

## Troubleshooting

### Common Issues

1. **"Architecture not found" error:**
   - Ensure `architecture_name = "custom"` in core module
   - Verify `"name": "custom"` in JSON file
   - Check ALZ provider library references

2. **JSON parsing errors:**
   - Validate JSON syntax with `jq`
   - Ensure all required fields are present
   - Check for trailing commas

3. **Management group creation fails:**
   - Verify `parent_id` references exist
   - Check Azure permissions for management group creation
   - Ensure unique `id` values

### Validation Commands

```bash
# 1. Validate JSON syntax
jq empty modules/core/lib/custom.alz_architecture_definition.json

# 2. Test terraform configuration  
terraform validate

# 3. Check plan output
terraform plan -var-file="environments/prod.tfvars" | grep -i "management"

# 4. Verify provider configuration
terraform providers
```

## Version Compatibility

- **ALZ Provider:** ~> 0.17 (supports library_references)
- **ALZ Library:** 2025.02.0 (latest as of implementation)
- **Terraform:** >= 1.9

## Best Practices

1. **Keep it Simple:** Start with the provided structure before making major changes
2. **Test Thoroughly:** Always run `terraform plan` after modifications
3. **Version Control:** Track changes to the architecture file
4. **Documentation:** Update this file when making structural changes
5. **Backup:** Keep a working copy before major modifications

## Related Changes

This custom architecture also affects:

- **Peering Names:** VNet peering names are simplified (no environment prefix)
- **Resource Naming:** Some resources reference management group names
- **Policy Assignments:** Applied at the custom management group levels

See [PEERING_CHANGES.md](PEERING_CHANGES.md) for details on peering modifications.
