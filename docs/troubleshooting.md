# Troubleshooting Guide

This guide covers common issues and solutions when deploying and managing Azure Landing Zones with advanced VM configurations including multiple NICs and data disks.

## Quick Diagnostics

### Common Commands

```bash
# Check Terraform state
terraform state list
terraform state show <resource_name>

# Validate configuration
terraform validate
terraform fmt -recursive .

# Check Azure resources
az vm list --output table
az network nic list --output table
az disk list --output table

# Azure connectivity test
az account show
az account list-locations --output table
```

## Deployment Issues

### Terraform Initialization Problems

**Error**: `Failed to initialize provider`

```hcl
Error: Failed to configure the Microsoft Azure Provider: building AzureRM Client: obtain subscription from Azure CLI: parsing json result from the Azure CLI: waiting for the Azure CLI: exit status 1
```

**Solutions**:

1. Re-authenticate with Azure:

   ```bash
   az logout
   az login
   az account set --subscription "your-subscription-id"
   ```

2. Clear Terraform cache:

   ```bash
   rm -rf .terraform
   rm .terraform.lock.hcl
   terraform init
   ```

3. Check provider version compatibility:

   ```hcl
   terraform {
     required_providers {
       azurerm = {
         source  = "hashicorp/azurerm"
         version = "~> 4.0"
       }
     }
   }
   ```

### Subscription and Permission Issues

**Error**: `Authorization failed` or `Insufficient privileges`

**Solutions**:

1. Verify subscription access:

   ```bash
   az account list --output table
   az role assignment list --assignee $(az account show --query user.name -o tsv)
   ```

2. Required roles:
   - Owner or Contributor at subscription level
   - User Access Administrator for RBAC assignments

3. Register required providers:

   ```bash
   az provider register -n Microsoft.VirtualMachineImages
   az provider register -n Microsoft.Compute
   az provider register -n Microsoft.Network
   az provider register -n Microsoft.Storage
   ```

### Resource Naming Conflicts

**Error**: `Resource already exists` with VM names like DC01, WEB01

**Solutions**:

1. Check existing resources:

   ```bash
   az vm list --query "[].name" --output table
   az network nic list --query "[].name" --output table
   ```

2. Use different resource group or change `vm_name_prefix`:

   ```hcl
   virtual_machines = {
     "dc" = {
       vm_name_prefix = "MYDC"  # Creates MYDC01, MYDC02
     }
   }
   ```

3. Clean up existing resources if safe:

   ```bash
   az vm delete --name DC01 --resource-group rg-identity-prod-uks --yes
   az network nic delete --name DC01-nic01 --resource-group rg-identity-prod-uks
   ```

## Virtual Machine Issues

### VM Creation Failures

**Error**: `VM size not available in availability zone`

**Solutions**:

1. Check available VM sizes:

   ```bash
   az vm list-sizes --location "UK South" --output table
   az vm list-skus --location "UK South" --zone --output table
   ```

2. Use different VM size or availability zone:

   ```hcl
   virtual_machines = {
     "app" = {
       vm_size = "Standard_D2s_v5"  # Instead of unavailable size
       availability_zones = ["1"]    # Single zone if multi-zone unavailable
     }
   }
   ```

### Multiple NICs Configuration Issues

**Error**: `Network interface already attached` or NIC creation failures

**Diagnostic Steps**:

```bash
# Check NIC status
az network nic list --resource-group rg-spoke-prod-uks --output table

# Check subnet availability
az network vnet subnet show --name snet-web --vnet-name vnet-spoke-prod-uks --resource-group rg-spoke-prod-uks

# Check IP address conflicts
az network nic ip-config list --nic-name WEB01-nic01 --resource-group rg-spoke-prod-uks
```

**Solutions**:

1. Verify subnet configuration:

   ```hcl
   subnets = {
     "snet-web" = {
       address_prefixes = ["10.20.1.0/24"]  # Ensure sufficient IP space
     }
     "snet-app" = {
       address_prefixes = ["10.20.2.0/24"]  # Different subnet for second NIC
     }
   }
   ```

2. Check static IP conflicts:

   ```hcl
   network_interfaces = [
     {
       subnet_name                  = "snet-web"
       private_ip_allocation_method = "Static"
       static_ip_address           = "10.20.1.10"  # Ensure unique IP
     }
   ]
   ```

3. Verify NSG rules allow traffic:

   ```bash
   az network nsg rule list --resource-group rg-spoke-prod-uks --nsg-name nsg-web --output table
   ```

### Data Disk Issues

**Error**: `Disk already attached` or LUN conflicts

**Diagnostic Steps**:

```bash
# Check disk status
az disk list --resource-group rg-spoke-prod-uks --output table

# Check VM disk configuration
az vm show --name WEB01 --resource-group rg-spoke-prod-uks --query "storageProfile.dataDisks"
```

**Solutions**:

1. Verify unique LUN assignments:

   ```hcl
   data_disks = [
     {
       size_gb = 512
       lun     = 0        # Must be unique per VM
     },
     {
       size_gb = 256
       lun     = 1        # Different LUN
     }
   ]
   ```

2. Check disk attachment status:

   ```bash
   az vm disk detach --name WEB01-datadisk01 --resource-group rg-spoke-prod-uks --vm-name WEB01
   ```

3. Resolve storage account conflicts:

   ```hcl
   data_disks = [
     {
       storage_account_type = "Premium_LRS"  # Ensure supported in region
       size_gb             = 256             # Within supported limits
     }
   ]
   ```

### Write Accelerator Issues

**Error**: `Write Accelerator not supported`

**Solutions**:

1. Check VM series support:

   ```bash
   az vm list-sizes --location "UK South" --query "[?contains(name, 'M')] | [?contains(name, 's')]"
   ```

2. Verify disk requirements:

   ```hcl
   data_disks = [
     {
       storage_account_type      = "Premium_LRS"        # Required
       write_accelerator_enabled = true
       caching                   = "None"               # Required for Write Accelerator
       size_gb                   = 256                  # ≥ 512 GB recommended
     }
   ]
   ```

## Network Connectivity Issues

### Hub-Spoke Connectivity Problems

**Error**: Spoke VMs cannot reach hub services or internet

**Diagnostic Steps**:

1. Check routing tables:

   ```bash
   az network route-table list --output table
   az network route-table route list --route-table-name rt-spoke --resource-group rg-connectivity-prod-uks
   ```

2. Verify peering status:

   ```bash
   az network vnet peering list --vnet-name vnet-hub-prod-uks --resource-group rg-connectivity-prod-uks
   ```

3. Test connectivity:

   ```bash
   # From VM in spoke
   ping 10.0.0.4    # Azure Firewall private IP
   nslookup google.com 10.0.0.4
   ```

**Solutions**:

1. Check firewall rules:

   ```bash
   az network firewall policy rule-collection-group list --policy-name pol-azfw-prod-uks --resource-group rg-connectivity-prod-uks
   ```

2. Verify route table assignment:

   ```hcl
   subnets = {
     "snet-workload" = {
       address_prefixes = ["10.20.1.0/24"]
       route_table_id   = "/subscriptions/.../routeTables/rt-spoke"
     }
   }
   ```

### Azure Firewall Issues

**Error**: Traffic blocked by Azure Firewall

**Solutions**:

1. Check firewall logs:

   ```bash
   az monitor log-analytics query --workspace workspace-id \
     --analytics-query "AzureDiagnostics | where Category == 'AzureFirewallApplicationRule' | limit 50"
   ```

2. Add required firewall rules:

   ```hcl
   application_rule_collections = [
     {
       name     = "AllowWindowsUpdate"
       priority = 1000
       action   = "Allow"
       rules = [
         {
           name             = "WindowsUpdate"
           source_addresses = ["10.20.0.0/16"]
           target_fqdns     = ["*.update.microsoft.com", "*.windowsupdate.com"]
           protocols = [
             {
               type = "Http"
               port = 80
             },
             {
               type = "Https"  
               port = 443
             }
           ]
         }
       ]
     }
   ]
   ```

### DNS Resolution Issues

**Error**: Cannot resolve domain names from VMs

**Solutions**:

1. Check DNS settings:

   ```bash
   az network vnet show --name vnet-spoke-prod-uks --resource-group rg-spoke-prod-uks --query "dhcpOptions.dnsServers"
   ```

2. Configure custom DNS:

   ```hcl
   virtual_network = {
     dns_servers = ["10.1.1.4", "10.1.1.5"]  # Domain controller IPs
   }
   ```

3. Verify domain controller connectivity:

   ```bash
   # From VM
   nslookup contoso.com 10.1.1.4
   telnet 10.1.1.4 53
   ```

## Azure Virtual Desktop Issues

### FSLogix Storage Account Errors

**Error**: `InvalidHeaderValue: The value for one of the HTTP headers is not in the correct format`

**Solutions**:

1. Check storage account network access rules:

   ```hcl
   network_rules = {
     default_action = "Allow"  # Temporary for initial deployment
     ip_rules       = ["YOUR_IP_ADDRESS"]  # Without /32 CIDR
   }
   ```

2. Remove metadata from Premium FileStorage file shares:

   ```hcl
   resource "azurerm_storage_share" "fslogix_profiles" {
     name               = "profiles"
     storage_account_id = module.fslogix_storage_account[0].resource_id
     quota              = 100
     enabled_protocol   = "SMB"
     # Remove access_tier and metadata for Premium FileStorage
   }
   ```

**Error**: `SubnetsHaveNoServiceEndpointsConfigured: Microsoft.Storage`

**Solutions**:

1. Add Microsoft.Storage service endpoint to AVD subnets:

   ```hcl
   subnets = {
     "snet-desktop" = {
       address_prefixes  = ["10.3.1.0/24"]
       service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
     }
   }
   ```

### AVD Tagging Issues

**Error**: Tags not appearing on host pool, workspace, application group, or scaling plan

**Root Cause**: Known issue with AVM pattern module version 0.3.x where tags are not properly merged

**Solutions**:

1. Update to latest module version:

   ```hcl
   module "avd_management_plane" {
     source  = "Azure/avm-ptn-avd-lza-managementplane/azurerm"
     version = "~> 0.3.2"  # Use latest 0.3.x version
   }
   ```

2. Verify tag parameters are correctly named:

   ```hcl
   virtual_desktop_host_pool_tags         = local.avd_tags
   virtual_desktop_workspace_tags         = local.avd_tags  
   virtual_desktop_application_group_tags = local.avd_tags
   virtual_desktop_scaling_plan_tags      = local.avd_tags
   ```

## Azure Image Builder Issues

### Image Template Naming Case Issues

**Error**: Image templates and definitions using incorrect case (e.g., "Test" instead of "test")

**Solutions**:

1. Ensure consistent lowercase naming in AIB module:

   ```hcl
   # In AIB naming.tf
   env_prefix = lower(var.environment)
   
   # Use env_prefix instead of var.environment
   name = "${image_config.name}-${local.env_prefix}"
   ```

### IP Address CIDR Validation

**Error**: `"81.129.180.16/32" must start with IPV4 address and/or slash, number of bits (0-30)`

**Solutions**:

1. Remove /32 CIDR notation for single IP addresses:

   ```hcl
   # In main.tf
   combined_allow_list_ip = concat(
     [trimspace(data.http.ip.response_body)],  # Without /32
     var.allow_list_ip != null ? var.allow_list_ip : []
   )
   ```

## Storage Issues

### Premium Disk Performance

**Error**: Poor disk performance despite Premium SSD

**Solutions**:

1. Check VM series support for Premium storage:

   ```bash
   az vm list-sizes --location "UK South" --query "[?contains(name, 's')]" --output table
   ```

2. Verify disk caching:

   ```hcl
   data_disks = [
     {
       caching = "ReadOnly"    # For read-heavy workloads
       # OR
       caching = "ReadWrite"   # For balanced workloads
       # OR  
       caching = "None"        # For write-heavy workloads
     }
   ]
   ```

3. Monitor disk metrics:

   ```bash
   az monitor metrics list --resource /subscriptions/.../disks/WEB01-datadisk01 \
     --metric "Disk Read IOPS" --interval PT1M
   ```

### Encryption Issues

**Error**: Disk encryption failures with customer-managed keys

**Solutions**:

1. Verify Key Vault permissions:

   ```bash
   az keyvault show --name kv-security-prod-uks --query "properties.accessPolicies[?permissions.keys[?contains(@, 'decrypt')]]"
   ```

2. Check disk encryption set:

   ```bash
   az disk-encryption-set show --name des-security-prod-uks --resource-group rg-security-prod-uks
   ```

3. Verify key vault key:

   ```hcl
   disk_encryption_set_id = "/subscriptions/.../diskEncryptionSets/des-security-prod-uks"
   
   # Ensure Key Vault allows disk encryption service
   key_vault_access_policy = {
     object_id = data.azurerm_client_config.current.object_id
     key_permissions = [
       "Get", "WrapKey", "UnwrapKey", "Decrypt", "Encrypt"
     ]
   }
   ```

## Identity and Domain Issues

### Domain Controller Problems

**Error**: Domain controllers not responding or replicating

**Diagnostic Steps**:

1. Check DC connectivity:

   ```bash
   # From domain controller
   dcdiag /a /e /v
   repadmin /replsummary
   ```

2. Verify DNS configuration:

   ```bash
   nslookup contoso.com
   nslookup _ldap._tcp.contoso.com
   ```

**Solutions**:

1. Check data disk for AD DS:

   ```hcl
   data_disks = [
     {
       size_gb = 256
       caching = "None"      # Critical for AD DS
       lun     = 0
     }
   ]
   ```

2. Verify network connectivity:

   ```bash
   # Required ports for AD DS
   telnet dc02 389   # LDAP
   telnet dc02 636   # LDAPS
   telnet dc02 3268  # Global Catalog
   ```

### Azure AD Connect Issues

**Error**: Hybrid identity synchronization failures

**Solutions**:

1. Check outbound connectivity:

   ```bash
   # From Azure AD Connect server
   Test-NetConnection login.microsoftonline.com -Port 443
   ```

2. Verify service account permissions:

   ```powershell
   # Check sync service account
   Get-ADUser -Identity "MSOL_*" -Properties *
   ```

## Backup and Recovery Issues

### VM Backup Policy Compliance

**Issue**: VMs showing as non-compliant in Azure Policy backup audit reports

> **⚠️ Note**: The landing zone uses audit policies for backup compliance monitoring. Backup protection must be configured through spoke module settings or manual assignment.

**Solutions**:

1. **Enable backup via spoke module** (Recommended):

   ```hcl
   # In spoke configuration
   enable_backup = true
   ```

2. **Check compliance in Azure Policy**:

   ```bash
   # View policy compliance in Azure Portal
   # Policy > Compliance > Search for "Backup Audit" policies
   ```

3. **Manual backup protection** (if needed):

   ```bash
   az backup protection enable-for-vm \
     --resource-group rg-spoke-prod-uks \
     --vault-name rsv-backup-prod-uks \
     --vm WEB01 \
     --policy-name VM-Standard-30Day-Daily-Policy
   ```

4. **Check backup policies are available**:

   ```bash
   az backup policy list --resource-group rg-management-prod-uks --vault-name rsv-backup-prod-uks
   ```

> **⚠️ AVM Issue**: The original "Deploy-VM-Backup" policy from ALZ is disabled due to AVM library inheritance issues. Use the audit policies above for compliance monitoring and configure backup protection through spoke modules or manual assignment.

### Recovery Services Vault Issues

**Error**: Cannot create backup items

**Solutions**:

1. Verify vault permissions:

   ```bash
   az role assignment list --assignee $(az account show --query user.name -o tsv) --scope /subscriptions/.../vaults/rsv-backup-prod-uks
   ```

2. Check vault cross-region settings:

   ```hcl
   backup_config = {
     cross_region_restore_enabled = true
     storage_mode_type           = "GeoRedundant"
   }
   ```

## Performance Issues

### VM Performance Problems

**Error**: High CPU or memory usage, slow response times

**Diagnostic Steps**:

1. Check VM metrics:

   ```bash
   az monitor metrics list --resource /subscriptions/.../virtualMachines/WEB01 \
     --metric "Percentage CPU" --interval PT5M
   ```

2. Analyze performance counters:

   ```bash
   # In Azure Monitor Log Analytics
   Perf
   | where ObjectName == "Processor" and CounterName == "% Processor Time"
   | where Computer == "WEB01"
   | summarize avg(CounterValue) by bin(TimeGenerated, 5m)
   ```

**Solutions**:

1. Scale up VM size:

   ```hcl
   vm_size = "Standard_D8s_v5"  # More CPU/memory
   ```

2. Enable accelerated networking:

   ```hcl
   network_interfaces = [
     {
       enable_accelerated_networking = true
     }
   ]
   ```

3. Optimize disk performance:

   ```hcl
   data_disks = [
     {
       storage_account_type = "Premium_LRS"
       size_gb             = 1024    # Larger disks = more IOPS
     }
   ]
   ```

### Network Performance Issues

**Error**: High latency or packet loss between tiers

**Solutions**:

1. Check placement groups:

   ```bash
   az vm show --name WEB01 --resource-group rg-spoke-prod-uks --query "virtualMachineScaleSet"
   ```

2. Use proximity placement groups for low latency:

   ```hcl
   proximity_placement_group_id = "/subscriptions/.../proximityPlacementGroups/ppg-app-tier"
   ```

3. Enable accelerated networking:

   ```hcl
   enable_accelerated_networking = true  # Reduces latency
   ```

## Monitoring and Logging Issues

### Log Analytics Issues

**Error**: Logs not flowing to Log Analytics workspace

**💡 Note**: With AMA integration, monitoring setup is now automatic via Azure Policy when both `management_config.enabled = true` and `core_config.enabled = true`.

**Solutions**:

1. Check Azure Monitor Agent installation (automatic via policy):

   ```bash
   az vm extension show --vm-name WEB01 --resource-group rg-spoke-prod-uks --name AzureMonitorWindowsAgent
   ```

2. Verify data collection rules (auto-created by management module):

   ```bash
   az monitor data-collection rule list --resource-group rg-management-prod-uks
   # Should show: dcr-vm-insights, dcr-change-tracking, dcr-defender-sql
   ```

3. Check policy compliance for automatic agent deployment:

   ```bash
   az policy state list --resource-group rg-spoke-prod-uks --query "[?contains(policyDefinitionName,'AMA') || contains(policyDefinitionName,'Monitor')]"
   ```

4. Verify workspace permissions (auto-configured by UAMI):

   ```bash
   az role assignment list --scope /subscriptions/.../workspaces/law-management-prod-uks
   ```

### Missing Security Events

**Error**: Security events not appearing in workspace

**Solutions**:

1. Verify security solution installation:

   ```bash
   az vm extension list --vm-name WEB01 --resource-group rg-spoke-prod-uks --query "[?name=='MicrosoftDefenderForServers']"
   ```

2. Check data collection configuration:

   ```hcl
   # In Log Analytics workspace
   solutions = [
     "Security",
     "SecurityCenterFree"
   ]
   ```

## Common Error Messages

### Terraform Errors

| Error | Solution |
|-------|----------|
| `Error: building AzureRM Client` | Re-run `az login` and set subscription |
| `Error: creating resource group` | Check permissions and naming conflicts |
| `Error: subnet already exists` | Use `terraform import` or different names |
| `Error: VM extension failed` | Check VM agent status and retry |

### Azure Errors

| Error | Solution |
|-------|----------|
| `SkuNotAvailable` | Use different VM size or region |
| `QuotaExceeded` | Request quota increase or use smaller resources |
| `ResourceNotFound` | Check resource names and resource group |
| `NetworkSecurityGroupNotFound` | Verify NSG exists and name is correct |

## Getting Help

### Diagnostic Information to Collect

```bash
# Terraform state info
terraform state list > terraform-resources.txt
terraform show > terraform-state.txt

# Azure resource info
az vm list --output json > azure-vms.json
az network nic list --output json > azure-nics.json
az disk list --output json > azure-disks.json

# Logs
az monitor log-analytics query --workspace <workspace-id> \
  --analytics-query "AzureDiagnostics | where TimeGenerated > ago(1h) | limit 100" \
  --output json > azure-logs.json
```

### Support Resources

- **Microsoft Support**: For Azure platform issues
- **HashiCorp Terraform**: For Terraform-specific problems  
- **Azure Verified Modules**: For AVM module issues
- **Community Forums**: Azure Tech Community, Stack Overflow

### Emergency Procedures

1. **VM Not Responding**:

   ```bash
   az vm restart --name VM01 --resource-group rg-spoke-prod-uks
   az vm deallocate --name VM01 --resource-group rg-spoke-prod-uks
   az vm start --name VM01 --resource-group rg-spoke-prod-uks
   ```

2. **Network Connectivity Lost**:
   - Check NSG rules
   - Verify route tables
   - Test Azure Firewall rules
   - Use Azure Bastion for access

3. **Complete Environment Recovery**:

   ```bash
   # Restore from backup
   az backup restore restore-disks --resource-group recovery-rg \
     --vault-name rsv-backup-prod-uks --item-name VM01 \
     --rp-name recovery-point-name --target-resource-group rg-spoke-prod-uks
   ```
