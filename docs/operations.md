# Operations Guide

This guide covers day-2 operations for managing your Azure Landing Zone, including VM management with multiple NICs and data disks, monitoring, maintenance, and troubleshooting procedures.

## Overview

Post-deployment operations ensure your Azure Landing Zone remains secure, performant, and compliant. This includes:

- **Infrastructure Management**: VM lifecycle, storage management, networking
- **Management Services**: Log Analytics workspace, optional Automation Account
- **Security Operations**: Monitoring, incident response, compliance
- **Performance Monitoring**: Resource utilization, optimization  
- **Backup and Recovery**: Data protection and disaster recovery
- **Cost Management**: Resource optimization and cost control

## Daily Operations

### Infrastructure Health Checks

#### VM Health Monitoring

```bash
# Check VM status across all resource groups
az vm list --show-details --query "[?powerState=='VM running'].{Name:name, ResourceGroup:resourceGroup, Size:hardwareProfile.vmSize, PowerState:powerState}" -o table

# Check VM performance metrics
az monitor metrics list \
  --resource "/subscriptions/{subscription-id}/resourceGroups/{rg-name}/providers/Microsoft.Compute/virtualMachines/{vm-name}" \
  --metric "Percentage CPU" \
  --interval PT1H \
  --start-time 2024-01-01T00:00:00Z
```

#### Network Interface Management

```bash
# List all NICs and their configurations
az network nic list --query "[].{Name:name, ResourceGroup:resourceGroup, PrivateIP:ipConfigurations[0].privateIpAddress, Subnet:ipConfigurations[0].subnet.id}" -o table

# Check NIC metrics for performance
az monitor metrics list \
  --resource "/subscriptions/{subscription-id}/resourceGroups/{rg-name}/providers/Microsoft.Network/networkInterfaces/{nic-name}" \
  --metric "BytesReceivedRate,BytesSentRate" \
  --interval PT1H
```

#### Storage Management

```bash
# Monitor disk performance
az monitor metrics list \
  --resource "/subscriptions/{subscription-id}/resourceGroups/{rg-name}/providers/Microsoft.Compute/disks/{disk-name}" \
  --metric "Composite Disk Read IOPS,Composite Disk Write IOPS" \
  --interval PT1H

# Check disk space utilization (requires Log Analytics)
Perf
| where CounterName == "% Free Space"
| where Computer startswith "WEB01" or Computer startswith "APP01" or Computer startswith "DB01"
| summarize avg(CounterValue) by Computer, InstanceName
| order by avg_CounterValue asc
```

### Log Analytics Queries

#### VM Performance Monitoring

```kusto
// CPU utilization across all VMs
Perf
| where CounterName == "% Processor Time"
| where TimeGenerated > ago(24h)
| summarize avg(CounterValue) by Computer
| order by avg_CounterValue desc

// Memory utilization
Perf
| where CounterName == "% Committed Bytes In Use"
| where TimeGenerated > ago(24h)
| summarize avg(CounterValue) by Computer
| order by avg_CounterValue desc

// Disk performance by VM and disk
Perf
| where CounterName in ("Disk Reads/sec", "Disk Writes/sec", "% Disk Time")
| where TimeGenerated > ago(24h)
| summarize avg(CounterValue) by Computer, CounterName, InstanceName
| order by Computer, CounterName, avg_CounterValue desc
```

#### Network Performance

```kusto
// Network utilization by NIC
Perf
| where CounterName in ("Bytes Received/sec", "Bytes Sent/sec")
| where TimeGenerated > ago(24h)
| summarize avg(CounterValue) by Computer, InstanceName
| order by avg_CounterValue desc

// Network errors and dropped packets
Perf
| where CounterName in ("Packets Received Discarded", "Packets Outbound Discarded")
| where TimeGenerated > ago(24h)
| where CounterValue > 0
| summarize sum(CounterValue) by Computer, InstanceName
```

#### Security Monitoring

```kusto
// Failed login attempts
SecurityEvent
| where EventID == 4625  // Failed logon
| where TimeGenerated > ago(24h)
| summarize FailedAttempts = count() by Computer, Account
| order by FailedAttempts desc

// Privilege escalation events
SecurityEvent
| where EventID in (4672, 4673, 4674)  // Special privileges assigned/used
| where TimeGenerated > ago(24h)
| summarize count() by Computer, Account, EventID

// Suspicious network connections
VMConnection
| where TimeGenerated > ago(24h)
| where Direction == "outbound"
| where RemoteIp !startswith "10." and RemoteIp !startswith "192.168." and RemoteIp !startswith "172."
| summarize count() by Computer, RemoteIp, ProcessName
| order by count_ desc
```

## Weekly Operations

### VM Management

#### VM Maintenance and Updates

```bash
# Check update status
az vm run-command invoke \
  --resource-group myRG \
  --name myVM \
  --command-id RunPowerShellScript \
  --scripts "Get-WindowsUpdate -MicrosoftUpdate"

# Install Windows updates
az vm run-command invoke \
  --resource-group myRG \
  --name myVM \
  --command-id RunPowerShellScript \
  --scripts "Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot"
```

#### Storage Maintenance

```bash
# Optimize database disks (for SQL Server VMs)
az vm run-command invoke \
  --resource-group myRG \
  --name DB01 \
  --command-id RunPowerShellScript \
  --scripts "
    # Defragment database drives
    Optimize-Volume -DriveLetter F -ReTrim -Verbose
    Optimize-Volume -DriveLetter G -ReTrim -Verbose
    
    # Update database statistics
    sqlcmd -Q 'EXEC sp_updatestats'
  "

# Check disk health
az vm run-command invoke \
  --resource-group myRG \
  --name WEB01 \
  --command-id RunPowerShellScript \
  --scripts "
    Get-PhysicalDisk | Get-StorageReliabilityCounter
    Get-Disk | Get-Volume | Get-PartitionSupportedSize
  "
```

### Performance Optimization

#### VM Performance Tuning

```powershell
# Optimize web server performance
# Run on web tier VMs (WEB01, WEB02, WEB03)

# Configure IIS for performance
Import-Module IISAdministration
Set-IISConfigurationAttribute -ConfigurationPath 'system.webServer/httpCompression' -AttributeName 'directory' -AttributeValue 'F:\IISTemp\Compression'
Set-IISConfigurationAttribute -ConfigurationPath 'system.webServer/httpCompression/scheme[@name="gzip"]' -AttributeName 'dynamicCompressionLevel' -AttributeValue 9

# Optimize network adapter settings for multiple NICs
Get-NetAdapter | Where-Object {$_.Name -like "*Ethernet*"} | ForEach-Object {
    Set-NetAdapterAdvancedProperty -Name $_.Name -DisplayName "Receive Side Scaling" -DisplayValue "Enabled"
    Set-NetAdapterAdvancedProperty -Name $_.Name -DisplayName "RSS Queues" -DisplayValue "4"
}
```

#### Database Performance Optimization

```sql
-- Run on database servers (DB01, DB02)
-- Optimize SQL Server for multiple data disks

-- Configure TempDB on dedicated disk (datadisk03)
ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev, FILENAME = 'H:\TempDB\tempdb.mdf', SIZE = 1024MB, FILEGROWTH = 256MB);
ALTER DATABASE tempdb MODIFY FILE (NAME = templog, FILENAME = 'H:\TempDB\templog.ldf', SIZE = 256MB, FILEGROWTH = 64MB);

-- Configure database files on appropriate disks
-- Main database files on datadisk01 (F: drive - Premium SSD with Write Accelerator)
-- Transaction logs on datadisk02 (G: drive - Premium SSD with Write Accelerator)

-- Enable database page compression
ALTER INDEX ALL ON [MyDatabase] REBUILD WITH (DATA_COMPRESSION = PAGE);

-- Update statistics and rebuild indexes weekly
EXEC sp_updatestats;
EXEC sp_MSforeachtable 'ALTER INDEX ALL ON ? REBUILD WITH (DATA_COMPRESSION = PAGE, ONLINE = ON);'
```

## Monthly Operations

### Capacity Planning

#### Storage Capacity Analysis

```kusto
// Disk space trending
Perf
| where CounterName == "% Free Space"
| where TimeGenerated > ago(30d)
| summarize avg(CounterValue), min(CounterValue), max(CounterValue) by Computer, InstanceName
| where avg_CounterValue < 20  // Less than 20% free space
| order by avg_CounterValue asc
```

#### Performance Trending

```kusto
// CPU utilization trending over 30 days
Perf
| where CounterName == "% Processor Time"
| where TimeGenerated > ago(30d)
| summarize avg(CounterValue) by Computer, bin(TimeGenerated, 1d)
| render timechart
```

### Security Reviews

#### Access Review

```bash
# Review VM access and permissions
az role assignment list --scope "/subscriptions/{subscription-id}/resourceGroups/{rg-name}" --query "[].{PrincipalName:principalName, RoleDefinitionName:roleDefinitionName, Scope:scope}" -o table

# Check for unused or stale accounts
az ad user list --query "[?accountEnabled==false].{DisplayName:displayName, UserPrincipalName:userPrincipalName, LastSignIn:signInActivity.lastSignInDateTime}" -o table
```

#### Security Configuration Audit

```kusto
// Review security events for the past month
SecurityEvent
| where TimeGenerated > ago(30d)
| where EventID in (4624, 4625, 4634)  // Logon, failed logon, logoff
| summarize LoginAttempts = count() by Computer, Account, EventID
| order by LoginAttempts desc

// Check for privilege escalation
SecurityEvent
| where TimeGenerated > ago(30d)
| where EventID == 4672  // Special privileges assigned
| summarize count() by Computer, Account
| order by count_ desc
```

## Backup and Recovery Operations

### Backup Verification

```bash
# Check backup status for all VMs
az backup job list --resource-group myRG --vault-name myRecoveryVault --query "[].{Name:properties.entityFriendlyName, Status:properties.status, StartTime:properties.startTime, Duration:properties.duration}" -o table

# Test backup restore (create test VM from backup)
az backup restore restore-disks \
  --resource-group myRG \
  --vault-name myRecoveryVault \
  --container-name myVM \
  --item-name myVM \
  --storage-account myStorageAccount \
  --recovery-point-name {recovery-point-id}
```

### Disaster Recovery Testing

```bash
# Test failover to secondary region (if configured)
az backup restore restore-disks \
  --resource-group myRG-dr \
  --vault-name myRecoveryVault-dr \
  --container-name myVM \
  --item-name myVM \
  --storage-account myStorageAccount-dr \
  --recovery-point-name {latest-recovery-point}
```

## Cost Management

### Resource Optimization

#### Identify Underutilized Resources

```kusto
// Find VMs with low CPU utilization
Perf
| where CounterName == "% Processor Time"
| where TimeGenerated > ago(30d)
| summarize avg(CounterValue) by Computer
| where avg_CounterValue < 5  // Less than 5% average CPU
| order by avg_CounterValue asc
```

```bash
# Review VM sizes and costs
az vm list --show-details --query "[].{Name:name, Size:hardwareProfile.vmSize, ResourceGroup:resourceGroup}" -o table

# Get cost analysis
az consumption usage list --start-date 2024-01-01 --end-date 2024-01-31 --query "[?contains(instanceName, 'VM')].{Instance:instanceName, Cost:pretaxCost, Currency:currency}" -o table
```

#### Right-sizing Recommendations

```bash
# Get Azure Advisor recommendations
az advisor recommendation list --category cost --query "[?category=='Cost'].{Impact:impact, Problem:shortDescription.problem, Solution:shortDescription.solution}" -o table
```

### Storage Cost Optimization

```bash
# Identify unattached disks
az disk list --query "[?managedBy==null].{Name:name, ResourceGroup:resourceGroup, SizeGB:diskSizeGb, Tier:sku.tier, Status:diskState}" -o table

# Find old snapshots
az snapshot list --query "[?timeCreated<'2024-01-01'].{Name:name, ResourceGroup:resourceGroup, SizeGB:diskSizeGb, Created:timeCreated}" -o table
```

## Automation Scripts

### VM Lifecycle Management

```powershell
# PowerShell script for automated VM management
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$Operation  # Start, Stop, Restart, Update
)

# Get all VMs in resource group
$vms = Get-AzVM -ResourceGroupName $ResourceGroupName

foreach ($vm in $vms) {
    switch ($Operation) {
        "Start" {
            Write-Output "Starting VM: $($vm.Name)"
            Start-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -NoWait
        }
        "Stop" {
            Write-Output "Stopping VM: $($vm.Name)"
            Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -Force -NoWait
        }
        "Restart" {
            Write-Output "Restarting VM: $($vm.Name)"
            Restart-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -NoWait
        }
        "Update" {
            Write-Output "Installing updates on VM: $($vm.Name)"
            $runCommandScript = @"
                Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot
"@
            Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vm.Name -CommandId 'RunPowerShellScript' -ScriptString $runCommandScript
        }
    }
}
```

### Network Configuration Management

```bash
#!/bin/bash
# Script to validate network configuration across multiple NICs

RESOURCE_GROUP="myRG"
SUBSCRIPTION_ID="your-subscription-id"

# Function to check NIC configuration
check_nic_config() {
    local vm_name=$1
    echo "Checking NICs for VM: $vm_name"
    
    # Get all NICs for the VM
    nics=$(az vm show --resource-group $RESOURCE_GROUP --name $vm_name --query "networkProfile.networkInterfaces[].id" -o tsv)
    
    for nic in $nics; do
        nic_name=$(basename $nic)
        echo "  NIC: $nic_name"
        
        # Get NIC details
        az network nic show --ids $nic --query "{Name:name, PrivateIP:ipConfigurations[0].privateIpAddress, Subnet:ipConfigurations[0].subnet.id, AcceleratedNetworking:enableAcceleratedNetworking, IPForwarding:enableIpForwarding}" -o table
        
        # Check NSG assignment
        nsg=$(az network nic show --ids $nic --query "networkSecurityGroup.id" -o tsv)
        if [ ! -z "$nsg" ]; then
            echo "    NSG: $(basename $nsg)"
        else
            echo "    NSG: Not assigned"
        fi
    done
}

# Get all VMs and check their NIC configurations
vms=$(az vm list --resource-group $RESOURCE_GROUP --query "[].name" -o tsv)

for vm in $vms; do
    check_nic_config $vm
    echo "---"
done
```

## Monitoring and Alerting

### Custom Alert Rules

```bash
# Create CPU alert for high utilization
az monitor metrics alert create \
  --name "High CPU Usage" \
  --resource-group myRG \
  --scopes "/subscriptions/{subscription-id}/resourceGroups/myRG/providers/Microsoft.Compute/virtualMachines/WEB01" \
  --condition "avg Percentage CPU > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action-group myActionGroup

# Create disk space alert
az monitor metrics alert create \
  --name "Low Disk Space" \
  --resource-group myRG \
  --scopes "/subscriptions/{subscription-id}/resourceGroups/myRG/providers/Microsoft.Compute/disks/WEB01-datadisk01" \
  --condition "avg Percentage CPU > 90" \
  --window-size 15m \
  --evaluation-frequency 5m \
  --action-group myActionGroup
```

### Custom Dashboards

```json
{
  "properties": {
    "lenses": {
      "0": {
        "order": 0,
        "parts": {
          "0": {
            "position": {"x": 0, "y": 0, "rowSpan": 4, "colSpan": 6},
            "metadata": {
              "inputs": [{
                "name": "query",
                "value": "Perf | where CounterName == \"% Processor Time\" | where TimeGenerated > ago(1h) | summarize avg(CounterValue) by Computer | order by avg_CounterValue desc"
              }],
              "type": "Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/LogsDashboardPart"
            }
          }
        }
      }
    }
  }
}
```

## Troubleshooting Procedures

### Common Issues

#### VM Performance Issues

1. **High CPU Usage**:
   ```bash
   # Check running processes
   az vm run-command invoke --resource-group myRG --name myVM --command-id RunPowerShellScript --scripts "Get-Process | Sort-Object CPU -Descending | Select-Object -First 10"
   ```

2. **Memory Issues**:
   ```bash
   # Check memory usage
   az vm run-command invoke --resource-group myRG --name myVM --command-id RunPowerShellScript --scripts "Get-WmiObject -Class Win32_OperatingSystem | Select-Object @{Name='Memory Usage (%)';Expression={[math]::Round((($_.TotalVisibleMemorySize - $_.FreePhysicalMemory) / $_.TotalVisibleMemorySize) * 100, 2)}}"
   ```

3. **Disk Performance Issues**:
   ```bash
   # Check disk performance counters
   az vm run-command invoke --resource-group myRG --name myVM --command-id RunPowerShellScript --scripts "Get-Counter '\PhysicalDisk(*)\Disk Reads/sec', '\PhysicalDisk(*)\Disk Writes/sec', '\PhysicalDisk(*)\% Disk Time'"
   ```

#### Network Connectivity Issues

1. **NIC Configuration Issues**:
   ```bash
   # Verify NIC configuration
   az network nic show --name WEB01-nic01 --resource-group myRG --query "{PrivateIP:ipConfigurations[0].privateIpAddress, Subnet:ipConfigurations[0].subnet.id, NSG:networkSecurityGroup.id}" -o table
   ```

2. **Route Table Issues**:
   ```bash
   # Check effective routes
   az network nic show-effective-route-table --name WEB01-nic01 --resource-group myRG
   ```

3. **NSG Rule Issues**:
   ```bash
   # Check effective security rules
   az network nic list-effective-nsg --name WEB01-nic01 --resource-group myRG
   ```

For detailed troubleshooting procedures, see the [Troubleshooting Guide](TROUBLESHOOTING.md).

## Maintenance Windows

### Scheduled Maintenance

```bash
# Schedule maintenance window script
#!/bin/bash

# Stop non-critical VMs during maintenance
NON_CRITICAL_VMS=("DEV-DB01" "FE-DEV01" "FE-DEV02")

for vm in "${NON_CRITICAL_VMS[@]}"; do
    echo "Stopping $vm for maintenance..."
    az vm deallocate --resource-group myRG --name $vm --no-wait
done

# Perform maintenance on critical VMs one at a time
CRITICAL_VMS=("WEB01" "WEB02" "WEB03" "APP01" "APP02" "DB01" "DB02")

for vm in "${CRITICAL_VMS[@]}"; do
    echo "Maintaining $vm..."
    
    # Update the VM
    az vm run-command invoke --resource-group myRG --name $vm --command-id RunPowerShellScript --scripts "Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot"
    
    # Wait for reboot
    sleep 300
    
    # Verify VM is running
    while [[ $(az vm show --resource-group myRG --name $vm --show-details --query "powerState" -o tsv) != "VM running" ]]; do
        echo "Waiting for $vm to start..."
        sleep 30
    done
    
    echo "$vm maintenance completed"
done

# Restart non-critical VMs
for vm in "${NON_CRITICAL_VMS[@]}"; do
    echo "Starting $vm after maintenance..."
    az vm start --resource-group myRG --name $vm --no-wait
done
```

## Best Practices Summary

1. **Monitoring**: Implement comprehensive monitoring for all VMs and network components
2. **Automation**: Use scripts and Azure Automation for repetitive tasks
3. **Documentation**: Maintain up-to-date operational procedures
4. **Backup Testing**: Regularly test backup and recovery procedures
5. **Security**: Continuously monitor for security threats and vulnerabilities
6. **Performance**: Regular performance optimization and capacity planning
7. **Cost Management**: Monitor and optimize resource costs monthly
8. **Maintenance**: Schedule regular maintenance windows for updates and optimization

## Next Steps

- [Security Guide](SECURITY.md) - Security operations and monitoring
- [Troubleshooting Guide](TROUBLESHOOTING.md) - Detailed troubleshooting procedures
- [Configuration Guide](CONFIGURATION.md) - Advanced configuration options