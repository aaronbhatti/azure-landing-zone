#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Network, Az.Resources
<#
.SYNOPSIS
    Deallocates (stops) the DR Azure Firewall to save costs during non-DR periods.

.DESCRIPTION
    This script deallocates the DR firewall. The firewall
    can be restarted later using the Start-DR-Firewall script.
    
    IMPORTANT: Resource locks (ReadOnly or CanNotDelete) on the firewall or its 
    resource group will block deallocation. Remove locks before running.

.NOTES
    Author  : Aaron Bhatti
    Version : 1.0.2
    Date    : 2025-08-10
    
    Prerequisites:
    - Az.Accounts, Az.Network, Az.Resources modules
    - Managed Identity with appropriate permissions
    - No resource locks on firewall or resource group
#>

# ============= CONFIGURATION =============
$TenantId = "3ec094fc-4da6-40af-8073-0303aaa9c094"
$SubscriptionId = "c7f53b68-70fa-458f-9976-95d722f3312f"  # Connectivity subscription

# Target Firewall
$FirewallResourceGroup = "rg-dr-network-ukw-hub"
$FirewallName = "azfw-dr-hub-ukw"
$FirewallRegion = "UK West"

# Operation Settings
$WhatIfMode = $false           # Set to $true for dry run
$WaitTimeoutMinutes = 20       # Maximum time to wait for deallocation
$PollIntervalSeconds = 15      # How often to check status
# =========================================

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Check if running in Azure Automation
$isAzureAutomation = $null -ne $env:AUTOMATION_ASSET_ACCOUNTID

# Initialize transcript (local only)
if (-not $isAzureAutomation) {
    $transcriptPath = Join-Path $env:TEMP "StopDRFirewall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Start-Transcript -Path $transcriptPath -Force | Out-Null
}

# ============= HELPER FUNCTIONS =============

# Logging function with Azure Automation support
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    
    if ($isAzureAutomation) {
        switch ($Level) {
            'ERROR'   { Write-Error -Message $logMessage -ErrorAction Continue }
            'WARNING' { Write-Warning -Message $logMessage }
            'SUCCESS' { Write-Output "[SUCCESS] $logMessage" }
            default   { Write-Output "[INFO] $logMessage" }
        }
    } else {
        $colorMessage = "[$Level] $logMessage"
        switch ($Level) {
            'ERROR'   { Write-Host $colorMessage -ForegroundColor Red }
            'WARNING' { Write-Host $colorMessage -ForegroundColor Yellow }
            'SUCCESS' { Write-Host $colorMessage -ForegroundColor Green }
            default   { Write-Host $colorMessage }
        }
    }
}

function Normalize-Region([string]$r) { ($r -replace '\s+','').ToLowerInvariant() }
$targetRegionNorm = Normalize-Region $FirewallRegion

function In-TargetRegion($resource) { (Normalize-Region $resource.Location) -eq $targetRegionNorm }

# Diagnostics function with safe property access
function Dump-FwDiagnostics {
    param([string]$Rg,[string]$Name)
    try {
        $fw = Get-AzFirewall -ResourceGroupName $Rg -Name $Name -ErrorAction Stop
        $ip = $null
        if ($fw.IpConfigurations) {
            $ip = ($fw.IpConfigurations | Select-Object -First 1).PrivateIPAddress
        }
        $st = if ($fw.PSObject.Properties.Name -contains 'FirewallState') { $fw.FirewallState } else { '<null>' }
        Write-Log "FW diag: State=$st, Prov=$($fw.ProvisioningState), PrivateIP=$($ip ?? '<none>')" -Level INFO
        Write-Log "Allocation State: $(if($ip){'Allocated'}else{'Deallocated'})" -Level INFO
        
        if ($fw.IpConfigurations) {
            $fw.IpConfigurations | ForEach-Object {
                Write-Log "IPConfig: Name=$($_.Name) PrivateIP=$($_.PrivateIPAddress)" -Level INFO
            }
        } else { 
            Write-Log "No IpConfigurations present" -Level INFO 
        }
    } catch { 
        Write-Log "FW diag error: $($_.Exception.Message)" -Level ERROR 
    }
}

# Wait for firewall to be deallocated
function Wait-FirewallDeallocated {
    param(
        [Parameter(Mandatory)][string]$Rg,
        [Parameter(Mandatory)][string]$Name,
        [int]$TimeoutMinutes = $WaitTimeoutMinutes,
        [int]$PollSeconds = $PollIntervalSeconds
    )
    
    Write-Log "Waiting for firewall deallocation (timeout: ${TimeoutMinutes} minutes)..." -Level INFO
    $startTime = Get-Date
    $deadline = $startTime.AddMinutes($TimeoutMinutes)
    
    do {
        Start-Sleep -Seconds $PollSeconds
        
        # Check current state with safe property access
        $fw = Get-AzFirewall -ResourceGroupName $Rg -Name $Name -ErrorAction Stop
        $privateIp = $null
        if ($fw.IpConfigurations) {
            $privateIp = ($fw.IpConfigurations | Select-Object -First 1).PrivateIPAddress
        }
        $provState = $fw.ProvisioningState
        
        # Check if deallocated (no private IP and succeeded state)
        if (-not $privateIp -and $provState -eq 'Succeeded') {
            $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
            Write-Log "Firewall deallocated successfully (elapsed: ${elapsed}s)" -Level SUCCESS
            return $true
        }
        
        # Show current state
        $fwState = if ($fw.PSObject.Properties.Name -contains 'FirewallState') { 
            $fw.FirewallState 
        } else { 
            'N/A' 
        }
        
        Write-Log "Current state: State=$fwState, Provisioning=$provState, IP=$(if($privateIp){"$privateIp"}else{'<none>'})" -Level INFO
        
        # Check timeout
        if ((Get-Date) -ge $deadline) {
            Write-Log "Timeout waiting for firewall deallocation" -Level ERROR
            Dump-FwDiagnostics -Rg $Rg -Name $Name
            throw "Timed out waiting for firewall '$Name' to deallocate after ${TimeoutMinutes} minutes"
        }
        
    } while ($true)
}

# ============= MAIN EXECUTION =============
try {
    Write-Log "=== STOP DR FIREWALL OPERATION STARTED ===" -Level SUCCESS
    Write-Log "Target: $FirewallName in $FirewallResourceGroup" -Level INFO
    Write-Log "Region: $FirewallRegion" -Level INFO
    Write-Log "WhatIf Mode: $WhatIfMode" -Level INFO
    
    # === AUTHENTICATION ===
    Write-Log "Authenticating to Azure..." -Level INFO
    
    if ($isAzureAutomation) {
        Connect-AzAccount -Identity -Tenant $TenantId -Subscription $SubscriptionId -WarningAction SilentlyContinue | Out-Null
        Write-Log "Connected using Managed Identity" -Level SUCCESS
    } else {
        $context = Get-AzContext
        if (-not $context) {
            throw "Not connected to Azure. Please run Connect-AzAccount first."
        }
        Write-Log "Using existing Azure connection: $($context.Account.Id)" -Level INFO
    }
    
    # Set subscription context
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    Write-Log "Subscription context set: $SubscriptionId" -Level SUCCESS
    
    # === PRE-FLIGHT CHECKS ===
    Write-Log "=== PERFORMING PRE-FLIGHT CHECKS ===" -Level INFO
    
    # Check for resource locks
    Write-Log "Checking for resource locks..." -Level INFO
    $locks = Get-AzResourceLock -ResourceGroupName $FirewallResourceGroup -ErrorAction SilentlyContinue
    if ($locks) {
        $fwLocks = $locks | Where-Object { $_.ResourceName -eq $FirewallName -or -not $_.ResourceName }
        if ($fwLocks) {
            Write-Log "Found $($fwLocks.Count) resource lock(s) that may block deallocation:" -Level WARNING
            foreach ($lock in $fwLocks) {
                Write-Log "  - $($lock.Name) ($($lock.Properties.level))" -Level WARNING
            }
            Write-Log "Resource locks may prevent deallocation. Consider removing them first." -Level WARNING
        }
    } else {
        Write-Log "No resource locks found" -Level SUCCESS
    }
    
    # === GET FIREWALL STATUS ===
    Write-Log "Retrieving firewall status..." -Level INFO
    $firewall = Get-AzFirewall -ResourceGroupName $FirewallResourceGroup -Name $FirewallName -ErrorAction Stop
    
    # Validate region
    if (-not (In-TargetRegion $firewall)) {
        throw "Firewall '$FirewallName' is in region '$($firewall.Location)', expected '$FirewallRegion'"
    }
    
    # Check if Virtual WAN firewall (not supported)
    if ($firewall.VirtualHub) {
        throw "This script supports VNet-based Azure Firewall only (Virtual WAN firewall detected)"
    }
    
    # Check current allocation state with safe property access
    $currentPrivateIp = $null
    if ($firewall.IpConfigurations) {
        $currentPrivateIp = ($firewall.IpConfigurations | Select-Object -First 1).PrivateIPAddress
    }
    
    if (-not $currentPrivateIp) {
        Write-Log "Firewall is already deallocated (no private IP assigned)" -Level SUCCESS
        Write-Log "Nothing to do - firewall is already stopped" -Level INFO
        return
    }
    
    Write-Log "Firewall is currently allocated with IP: $currentPrivateIp" -Level INFO
    
    # === DEALLOCATE FIREWALL ===
    if ($WhatIfMode) {
        Write-Log "WHATIF: Would deallocate firewall '$FirewallName'" -Level WARNING
        Write-Log "WHATIF: Would remove IP configurations to stop the firewall" -Level WARNING
        Write-Log "WHATIF: Would wait up to $WaitTimeoutMinutes minutes for deallocation" -Level WARNING
        Write-Log "WHATIF: Estimated monthly savings: ~£500-800 (depending on configuration)" -Level WARNING
    } else {
        Write-Log "=== DEALLOCATING FIREWALL ===" -Level INFO
        
        try {
            Write-Log "Initiating firewall deallocation..." -Level INFO
            Write-Log "This will remove IP configurations and stop billing for compute resources" -Level INFO
            
            # Deallocate the firewall
            $firewall.Deallocate()
            
            Write-Log "Applying deallocation changes..." -Level INFO
            $result = $firewall | Set-AzFirewall
            
            if ($result) {
                Write-Log "Deallocation request submitted successfully" -Level SUCCESS
            } else {
                throw "Failed to submit deallocation request"
            }
            
        } catch {
            Write-Log "Failed to deallocate firewall: $($_.Exception.Message)" -Level ERROR
            Dump-FwDiagnostics -Rg $FirewallResourceGroup -Name $FirewallName
            throw
        }
        
        # Wait for deallocation to complete
        Write-Log "Waiting for deallocation to complete..." -Level INFO
        $deallocated = Wait-FirewallDeallocated `
            -Rg $FirewallResourceGroup `
            -Name $FirewallName `
            -TimeoutMinutes $WaitTimeoutMinutes `
            -PollSeconds $PollIntervalSeconds
        
        if ($deallocated) {
            Write-Log "=== FIREWALL SUCCESSFULLY DEALLOCATED ===" -Level SUCCESS
            Write-Log "The firewall is now stopped and not incurring compute charges" -Level INFO
            Write-Log "Configuration and rules are preserved and can be restarted anytime" -Level INFO
            
            # Final diagnostics
            Write-Log "=== FINAL STATE CHECK ===" -Level INFO
            Dump-FwDiagnostics -Rg $FirewallResourceGroup -Name $FirewallName
        }
    }
    
    Write-Log "=== OPERATION COMPLETED SUCCESSFULLY ===" -Level SUCCESS
    
} catch {
    Write-Log "OPERATION FAILED: $($_.Exception.Message)" -Level ERROR
    
    # Try to get current state for debugging
    try {
        Dump-FwDiagnostics -Rg $FirewallResourceGroup -Name $FirewallName
    } catch {
        Write-Log "Could not retrieve firewall diagnostics" -Level ERROR
    }
    
    if ($isAzureAutomation) {
        throw
    }
    
} finally {
    # Stop transcript if it was started
    if (-not $isAzureAutomation -and $transcriptPath) {
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Transcript saved to: $transcriptPath" -Level INFO
    }
    
    # Final status for Azure Automation
    if ($isAzureAutomation) {
        Write-Output "Script execution completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    }
}