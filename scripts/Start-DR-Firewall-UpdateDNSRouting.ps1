#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Network, Az.Resources
<#
.SYNOPSIS
    Start DR Firewall, wait for IP allocation, then update DNS and default routes.

.DESCRIPTION
    This script allocates (starts) the DR Azure Firewall and updates VNet DNS servers and route tables to point to the firewall's private IP.
    
    IMPORTANT: 
    - Script will check for and STOP if resource locks are detected
    - Remove resource locks (ReadOnly/CanNotDelete) on firewall and route tables before running
    - DR domain controllers should have STATIC IPs matching PROD set within the VM Network settings
    
.NOTES
    Author  : Aaron Bhatti
    Version : 1.0.0
    Date    : 2025-08-12
        
    Prerequisites:
    - Az.Accounts, Az.Network, Az.Resources modules
    - Managed Identity with appropriate permissions
    - No resource locks on firewall or route tables
#>

# ============= CONFIGURATION =============
$TenantId = "3ec094fc-4da6-40af-8073-0303aaa9c094"
$SubscriptionId = "c7f53b68-70fa-458f-9976-95d722f3312f"  # Connectivity subscription

# Target Firewall
$FirewallResourceGroup = "rg-dr-network-ukw-hub"
$FirewallName = "azfw-dr-hub-ukw"
$FirewallRegion = "UK West"

# Firewall Allocation Resources
$FwVNetRG = "rg-dr-network-ukw-hub"
$FwVNetName = "vnet-dr-hub-ukw"
$FwSubnetName = "AzureFirewallSubnet"

# Data (Frontend) Public IP - REQUIRED
$FwDataPipRG = "rg-dr-network-ukw-hub"
$FwDataPipName = "pip-azfw-dr-hub-ukw"  # Data PIP for DR firewall

# Management Public IP - OPTIONAL (leave blank if not using)
$FwMgmtPipRG = "rg-dr-network-ukw-hub"
$FwMgmtPipName = ""  # e.g. "pip-azfw-dr-hub-ukw-mgmt" or leave blank

# DNS Update Configuration
$DnsMode = "Replace"  # Replace | Append | Skip
$VNetList = @(
    @{ SubId="c7f53b68-70fa-458f-9976-95d722f3312f"; RG="rg-dr-network-ukw-hub";   Name="vnet-dr-hub-ukw" },
    @{ SubId="c7f53b68-70fa-458f-9976-95d722f3312f"; RG="rg-dr-identity-ukw-network";    Name="vnet-dr-identity-ukw" },
    @{ SubId="c7f53b68-70fa-458f-9976-95d722f3312f"; RG="rg-dr-infra-ukw-network";   Name="vnet-dr-infra-ukw" },
    @{ SubId="c7f53b68-70fa-458f-9976-95d722f3312f"; RG="rg-dr-avd-ukw-network";   Name="vnet-dr-avd-ukw" }
)

# Route Table Update Configuration
$DefaultRouteName = "defaultroute"
$DefaultRoutePrefix = "0.0.0.0/0"
$RouteTableList = @(
    @{ SubId="c7f53b68-70fa-458f-9976-95d722f3312f"; RG="rg-dr-infra-ukw-network";   Name="rt-dr-infra-ukw" },
    @{ SubId="c7f53b68-70fa-458f-9976-95d722f3312f"; RG="rg-dr-identity-ukw-network";    Name="rt-dr-identity-ukw" },
    @{ SubId="c7f53b68-70fa-458f-9976-95d722f3312f"; RG="rg-dr-avd-ukw-network";   Name="rt-dr-avd-ukw" }
)

# Operation Settings
$WhatIfMode = $false           # Set to $true for dry run
$ForceContinueWithLocks = $false  # Set to $true to continue despite locks (NOT RECOMMENDED)
$WaitTimeoutMinutes = 25       # Maximum time to wait for firewall allocation
$PollIntervalSeconds = 20      # How often to check status
# =========================================

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Check if running in Azure Automation
$isAzureAutomation = $null -ne $env:AUTOMATION_ASSET_ACCOUNTID

# Initialize transcript (local only)
if (-not $isAzureAutomation) {
    $transcriptPath = Join-Path $env:TEMP "StartDRFirewall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Start-Transcript -Path $transcriptPath -Force | Out-Null
}

# Track current subscription context
$script:_LastSubId = $null

# ============= HELPER FUNCTIONS =============

# Logging function with Azure Automation support
function Write-Log {
    param(
        [string]$Message,
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

# Subscription context management
function Use-Subscription {
    param([Parameter(Mandatory)][string]$SubscriptionId)
    
    if ($SubscriptionId -and $SubscriptionId -ne $script:_LastSubId) {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        $script:_LastSubId = $SubscriptionId
    }
}

# Check for resource locks function - COPIED FROM WORKING SCRIPT
function Test-ResourceLocks {
    param(
        [string[]]$ResourceGroups,
        [hashtable[]]$Resources
    )
    
    Write-Log "=== CHECKING FOR RESOURCE LOCKS ===" -Level INFO
    Write-Log "Function called with $($ResourceGroups.Count) resource groups" -Level INFO
    
    # Initialize return variables
    $allLocks = @()
    $locksFound = $false
    
    # Safety check
    if ($null -eq $ResourceGroups -or $ResourceGroups.Count -eq 0) {
        Write-Log "No resource groups provided to check" -Level WARNING
        return $false
    }
    
    Write-Log "Checking locks on target resource groups..." -Level INFO
    
    # Check locks on each resource group
    foreach ($rg in ($ResourceGroups | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($rg)) {
            Write-Log "  Skipping empty resource group name" -Level WARNING
            continue
        }
        
        # Find the subscription for this RG from Resources
        $rgSub = $null
        foreach ($res in $Resources) {
            if ($res.RG -eq $rg -and $res.SubId) {
                $rgSub = $res.SubId
                break
            }
        }
        
        # Use the found subscription or default to current
        if ($rgSub) {
            Write-Log "  Switching to subscription: $rgSub for RG: $rg" -Level INFO
            try {
                Set-AzContext -SubscriptionId $rgSub -ErrorAction Stop | Out-Null
            } catch {
                Write-Log "    Failed to switch subscription: $($_.Exception.Message)" -Level WARNING
                continue
            }
        } else {
            Write-Log "  Using current subscription for RG: $rg" -Level INFO
        }
        
        Write-Log "  Checking resource group: $rg" -Level INFO
        try {
            $rgLocks = @(Get-AzResourceLock -ResourceGroupName $rg -ErrorAction Stop)
            if ($rgLocks -and $rgLocks.Count -gt 0) {
                Write-Log "    Found $($rgLocks.Count) lock(s) on resource group $rg" -Level WARNING
                $allLocks += $rgLocks
                $locksFound = $true
            } else {
                Write-Log "    No locks found on resource group $rg" -Level INFO
            }
        } catch {
            $lockError = $_.Exception.Message
            Write-Log "    Could not check resource group locks: $lockError" -Level WARNING
        }
    }
    
    # Switch back to original subscription
    Write-Log "Switching back to original subscription: $SubscriptionId" -Level INFO
    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    } catch {
        Write-Log "  Warning: Could not switch back to original subscription" -Level WARNING
    }
    
    # Remove duplicates based on lock ID
    if ($allLocks.Count -gt 0) {
        Write-Log "Processing $($allLocks.Count) locks for duplicates" -Level INFO
        $uniqueLocks = $allLocks | Group-Object -Property ResourceId | ForEach-Object { $_.Group[0] }
        $allLocks = @($uniqueLocks)
        Write-Log "After deduplication: $($allLocks.Count) unique locks" -Level INFO
    }
    
    # Report findings
    if ($locksFound -and $allLocks.Count -gt 0) {
        Write-Log "=== ⚠️ RESOURCE LOCKS DETECTED ===" -Level ERROR
        Write-Log "Found $($allLocks.Count) lock(s) that will prevent proper operation:" -Level ERROR
        
        foreach ($lock in $allLocks) {
            Write-Log "  Lock Name: $($lock.Name)" -Level ERROR
            Write-Log "    Level: $($lock.Properties.level)" -Level ERROR
            Write-Log "    Scope: $($lock.ResourceId)" -Level INFO
            if ($lock.Properties.notes) {
                Write-Log "    Notes: $($lock.Properties.notes)" -Level INFO
            }
        }
        
        Write-Log "Returning TRUE - locks detected" -Level WARNING
        return $true
    } else {
        Write-Log "=== ✅ NO RESOURCE LOCKS DETECTED ===" -Level SUCCESS
        Write-Log "Returning FALSE - no locks found" -Level INFO
        return $false
    }
}

# Region normalization and validation
function Normalize-Region([string]$r) { 
    ($r -replace '\s+','').ToLowerInvariant() 
}

function In-TargetRegion($resource) { 
    $targetRegionNorm = Normalize-Region $FirewallRegion
    (Normalize-Region $resource.Location) -eq $targetRegionNorm 
}

# Firewall diagnostics with safe property access
function Get-FirewallDiagnostics {
    param(
        [string]$ResourceGroup,
        [string]$Name
    )
    
    try {
        # Ensure we're in the correct subscription for the firewall
        Use-Subscription -SubscriptionId $SubscriptionId
        
        $fw = Get-AzFirewall -ResourceGroupName $ResourceGroup -Name $Name -ErrorAction Stop
        
        # Extract private IP safely
        $privateIp = $null
        if ($fw.IpConfigurations) {
            if ($fw.IpConfigurations.Count -gt 0) {
                $privateIp = ($fw.IpConfigurations | Select-Object -First 1).PrivateIPAddress
            }
        }
        
        # Get firewall state safely
        $fwState = if ($fw.PSObject.Properties.Name -contains 'FirewallState') { 
            $fw.FirewallState 
        } else { 
            'N/A' 
        }
        
        Write-Log "Firewall Diagnostics:" -Level INFO
        Write-Log "  State: $fwState" -Level INFO
        Write-Log "  Provisioning State: $($fw.ProvisioningState)" -Level INFO
        Write-Log "  Private IP: $(if($privateIp){"$privateIp"}else{'<none>'})" -Level INFO
        Write-Log "  Allocation Status: $(if($privateIp){'Allocated'}else{'Deallocated'})" -Level INFO
        
    } catch {
        Write-Log "Failed to get firewall diagnostics: $($_.Exception.Message)" -Level ERROR
    }
}

# Wait for firewall to be ready with IP allocation
function Wait-FirewallReady {
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$Name,
        [int]$TimeoutMinutes = $WaitTimeoutMinutes,
        [int]$PollSeconds = $PollIntervalSeconds
    )
    
    Write-Log "Checking firewall readiness..." -Level INFO
    $startTime = Get-Date
    $deadline = $startTime.AddMinutes($TimeoutMinutes)
    
    try {
        # Check immediately without waiting (in case it's already ready)
        $fw = Get-AzFirewall -ResourceGroupName $ResourceGroup -Name $Name -ErrorAction Stop
        
        # Extract private IP safely - using same pattern as Get-FirewallDiagnostics
        $privateIp = $null
        if ($null -ne $fw) {
            # Check if property exists and is accessible
            try {
                if ($fw.IpConfigurations) {
                    if ($fw.IpConfigurations.Count -gt 0) {
                        $privateIp = ($fw.IpConfigurations | Select-Object -First 1).PrivateIPAddress
                    }
                }
            } catch {
                Write-Log "Note: IpConfigurations not accessible yet" -Level INFO
            }
        }
        
        # If already has IP and succeeded, return immediately
        if ($privateIp -and $fw.ProvisioningState -eq 'Succeeded') {
            Write-Log "Firewall already ready with IP: $privateIp" -Level SUCCESS
            return $fw, $privateIp
        }
        
        Write-Log "Firewall needs to complete allocation, waiting..." -Level INFO
        
    } catch {
        Write-Log "Initial firewall check failed, will retry: $($_.Exception.Message)" -Level INFO
    }
    
    # Enter polling loop
    do {
        Start-Sleep -Seconds $PollSeconds
        
        try {
            # Get current firewall state
            $fw = Get-AzFirewall -ResourceGroupName $ResourceGroup -Name $Name -ErrorAction Stop
            
            # Extract private IP safely
            $privateIp = $null
            if ($null -ne $fw) {
                try {
                    if ($fw.IpConfigurations) {
                        if ($fw.IpConfigurations.Count -gt 0) {
                            $privateIp = ($fw.IpConfigurations | Select-Object -First 1).PrivateIPAddress
                        }
                    }
                } catch {
                    # Property might not be accessible yet, continue waiting
                }
            }
            
            # Get firewall state safely
            $fwState = if ($fw.PSObject.Properties.Name -contains 'FirewallState') { 
                $fw.FirewallState 
            } else { 
                $null 
            }
            
            $provState = $fw.ProvisioningState
            
            # Log current status
            Write-Log "Current status: State=$(if($fwState){"$fwState"}else{'N/A'}), Provisioning=$provState, IP=$(if($privateIp){"$privateIp"}else{'<none>'})" -Level INFO
            
            # Check if ready (has IP, succeeded, and not explicitly stopped)
            $notExplicitlyStopped = -not $fwState -or $fwState -ne 'Stopped'
            if ($privateIp -and $provState -eq 'Succeeded' -and $notExplicitlyStopped) {
                $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
                Write-Log "Firewall ready with IP: $privateIp (elapsed: ${elapsed}s)" -Level SUCCESS
                return $fw, $privateIp
            }
            
            # Check for failure state
            if ($provState -eq 'Failed') {
                Write-Log "Firewall provisioning failed" -Level ERROR
                Get-FirewallDiagnostics -ResourceGroup $ResourceGroup -Name $Name
                throw "Firewall provisioning failed"
            }
            
        } catch {
            Write-Log "Error checking firewall state: $($_.Exception.Message)" -Level WARNING
        }
        
        # Check timeout
        if ((Get-Date) -ge $deadline) {
            Write-Log "Timeout waiting for firewall to be ready" -Level ERROR
            Get-FirewallDiagnostics -ResourceGroup $ResourceGroup -Name $Name
            throw "Timed out waiting for firewall '$Name' to be ready after ${TimeoutMinutes} minutes"
        }
        
    } while ($true)
}

# Resolve and validate firewall private IP
function Resolve-FirewallPrivateIp {
    param(
        $FirewallObject,
        $CandidateIp
    )
    
    $candidates = @()
    
    # Add candidate IP if provided
    if ($CandidateIp) { 
        $candidates += $CandidateIp 
    }
    
    # Add IP from IpConfigurations - using same safe pattern
    if ($FirewallObject.IpConfigurations) {
        if ($FirewallObject.IpConfigurations.Count -gt 0) {
            $ip = ($FirewallObject.IpConfigurations | Select-Object -First 1).PrivateIPAddress
            if ($ip) { 
                $candidates += $ip 
            }
        }
    }
    
    # Add management IP if exists
    if ($FirewallObject.ManagementIpConfiguration) {
        if ($FirewallObject.ManagementIpConfiguration.PrivateIPAddress) {
            $candidates += $FirewallObject.ManagementIpConfiguration.PrivateIPAddress
        }
    }
    
    # Process and validate candidates
    foreach ($candidate in $candidates) {
        if ($candidate -is [string]) {
            $candidate = $candidate.Trim()
            if ($candidate -match '^\d{1,3}(\.\d{1,3}){3}$') {
                return $candidate
            }
        }
    }
    
    return $null
}

# Update VNet DNS servers
function Update-VNetDns {
    param(
        [hashtable]$VNetDefinition,
        [string]$FirewallIp,
        [string]$Mode
    )
    
    Use-Subscription -SubscriptionId $VNetDefinition.SubId
    
    Write-Log "Processing VNet $($VNetDefinition.Name) in RG $($VNetDefinition.RG)" -Level INFO
    
    try {
        $vnet = Get-AzVirtualNetwork -ResourceGroupName $VNetDefinition.RG -Name $VNetDefinition.Name -ErrorAction Stop
        
        # Skip if wrong region
        if (-not (In-TargetRegion $vnet)) {
            Write-Log "  Skipping (wrong region: $($vnet.Location))" -Level INFO
            return
        }
        
        # Get current DNS servers
        $currentDns = @()
        if ($vnet.DhcpOptions -and $vnet.DhcpOptions.DnsServers) {
            $currentDns = @($vnet.DhcpOptions.DnsServers)
        }
        
        # Determine target DNS servers based on mode
        $targetDns = switch ($Mode) {
            "Replace" { @($FirewallIp) }
            "Append"  { @($currentDns + $FirewallIp) | Where-Object { $_ } | Select-Object -Unique }
            "Skip"    { $null }
        }
        
        if ($null -eq $targetDns) {
            Write-Log "  Skipping DNS update (mode: Skip)" -Level INFO
            return
        }
        
        # Check if update needed
        if (@($targetDns) -ne @($currentDns)) {
            $currentStr = if ($currentDns) { $currentDns -join "," } else { "none" }
            $targetStr = $targetDns -join ","
            
            Write-Log "  Updating DNS: $currentStr -> $targetStr" -Level INFO
            
            if (-not $WhatIfMode) {
                if (-not $vnet.DhcpOptions) {
                    $vnet.DhcpOptions = New-Object Microsoft.Azure.Commands.Network.Models.PSDhcpOptions
                }
                $vnet.DhcpOptions.DnsServers = @($targetDns)
                Set-AzVirtualNetwork -VirtualNetwork $vnet | Out-Null
                Write-Log "  DNS updated successfully" -Level SUCCESS
            } else {
                Write-Log "  WHATIF: Would update DNS servers" -Level WARNING
            }
        } else {
            Write-Log "  DNS already configured correctly" -Level INFO
        }
        
    } catch {
        Write-Log "  Failed to update VNet: $($_.Exception.Message)" -Level ERROR
    }
}

# Update route table default route
function Update-RouteTable {
    param(
        [hashtable]$RouteTableDefinition,
        [string]$FirewallIp
    )
    
    Use-Subscription -SubscriptionId $RouteTableDefinition.SubId
    
    Write-Log "Processing Route Table $($RouteTableDefinition.Name) in RG $($RouteTableDefinition.RG)" -Level INFO
    
    try {
        $routeTable = Get-AzRouteTable -ResourceGroupName $RouteTableDefinition.RG -Name $RouteTableDefinition.Name -ErrorAction Stop
        
        # Skip if wrong region
        if (-not (In-TargetRegion $routeTable)) {
            Write-Log "  Skipping (wrong region: $($routeTable.Location))" -Level INFO
            return
        }
        
        $needsUpdate = $false
        
        # Find existing default routes
        $routeByName = $routeTable.Routes | Where-Object { $_.Name -eq $DefaultRouteName }
        $defaultRoutes = @($routeTable.Routes | Where-Object { $_.AddressPrefix -eq $DefaultRoutePrefix })
        
        # Handle duplicate default routes
        if ($defaultRoutes.Count -gt 1) {
            Write-Log "  Found $($defaultRoutes.Count) default routes - removing duplicates" -Level WARNING
            
            if (-not $WhatIfMode) {
                # Remove all duplicates except the first
                foreach ($duplicate in $defaultRoutes | Select-Object -Skip 1) {
                    Write-Log "    Removing duplicate: $($duplicate.Name)" -Level INFO
                    Remove-AzRouteConfig -Name $duplicate.Name -RouteTable $routeTable | Out-Null
                    $needsUpdate = $true
                }
                
                if ($needsUpdate) {
                    Set-AzRouteTable -RouteTable $routeTable | Out-Null
                    # Refresh route table
                    $routeTable = Get-AzRouteTable -ResourceGroupName $RouteTableDefinition.RG -Name $RouteTableDefinition.Name
                    $routeByName = $routeTable.Routes | Where-Object { $_.Name -eq $DefaultRouteName }
                    $defaultRoutes = @($routeTable.Routes | Where-Object { $_.AddressPrefix -eq $DefaultRoutePrefix })
                    $needsUpdate = $false
                }
            } else {
                Write-Log "  WHATIF: Would remove duplicate default routes" -Level WARNING
            }
        }
        
        # Determine which route to update
        $targetRoute = $routeByName
        if (-not $targetRoute -and $defaultRoutes.Count -ge 1) {
            $targetRoute = $defaultRoutes[0]
        }
        
        if ($targetRoute) {
            # Update existing route if needed
            $needsRouteUpdate = ($targetRoute.NextHopType -ne "VirtualAppliance" -or $targetRoute.NextHopIpAddress -ne $FirewallIp)
            
            if ($needsRouteUpdate) {
                Write-Log "  Updating route $($targetRoute.Name) -> $FirewallIp" -Level INFO
                
                if (-not $WhatIfMode) {
                    Set-AzRouteConfig `
                        -Name $targetRoute.Name `
                        -AddressPrefix $DefaultRoutePrefix `
                        -NextHopType "VirtualAppliance" `
                        -NextHopIpAddress $FirewallIp `
                        -RouteTable $routeTable | Out-Null
                    $needsUpdate = $true
                } else {
                    Write-Log "  WHATIF: Would update route to point to $FirewallIp" -Level WARNING
                }
            } else {
                Write-Log "  Route already points to $FirewallIp" -Level INFO
            }
        } else {
            # Add new default route
            Write-Log "  Adding default route $DefaultRouteName -> $FirewallIp" -Level INFO
            
            if (-not $WhatIfMode) {
                Add-AzRouteConfig `
                    -Name $DefaultRouteName `
                    -AddressPrefix $DefaultRoutePrefix `
                    -NextHopType "VirtualAppliance" `
                    -NextHopIpAddress $FirewallIp `
                    -RouteTable $routeTable | Out-Null
                $needsUpdate = $true
            } else {
                Write-Log "  WHATIF: Would add default route" -Level WARNING
            }
        }
        
        # Commit changes if needed
        if (-not $WhatIfMode -and $needsUpdate) {
            Set-AzRouteTable -RouteTable $routeTable | Out-Null
            Write-Log "  Route table updated successfully" -Level SUCCESS
        }
        
    } catch {
        Write-Log "  Failed to update route table: $($_.Exception.Message)" -Level ERROR
    }
}

# ============= MAIN EXECUTION =============
try {
    Write-Log "=== START DR FIREWALL OPERATION STARTED ===" -Level SUCCESS
    Write-Log "Target: $FirewallName in $FirewallResourceGroup" -Level INFO
    Write-Log "Region: $FirewallRegion" -Level INFO
    Write-Log "WhatIf Mode: $WhatIfMode" -Level INFO
    Write-Log "Force Continue With Locks: $ForceContinueWithLocks" -Level INFO
    
    # Important notes
    Write-Log "IMPORTANT: Ensure DR domain controllers have STATIC IPs matching PRODUCTION" -Level WARNING
    $rtResourceGroups = ($RouteTableList | ForEach-Object { $_.RG } | Select-Object -Unique) -join ', '
    Write-Log "IMPORTANT: Remove resource locks on these route table RGs before running: $rtResourceGroups" -Level WARNING
    
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
    Use-Subscription -SubscriptionId $SubscriptionId
    Write-Log "Subscription context set: $SubscriptionId" -Level SUCCESS
    
    # === CHECK FOR RESOURCE LOCKS ===
    Write-Log "Starting resource lock check process..." -Level INFO
    
    # Build list of resource groups to check
    $resourceGroupsToCheck = @($FirewallResourceGroup)
    $resourceGroupsToCheck += $FwVNetRG
    $resourceGroupsToCheck += $FwDataPipRG
    if ($FwMgmtPipRG) { $resourceGroupsToCheck += $FwMgmtPipRG }
    $resourceGroupsToCheck += $VNetList | ForEach-Object { $_.RG }
    $resourceGroupsToCheck += $RouteTableList | ForEach-Object { $_.RG }
    $resourceGroupsToCheck = $resourceGroupsToCheck | Select-Object -Unique
    
    Write-Log "Resource groups to check: $($resourceGroupsToCheck -join ', ')" -Level INFO
    
    # Build list of specific resources to check
    $resourcesToCheck = @()
    $resourcesToCheck += @{ SubId=$SubscriptionId; RG=$FirewallResourceGroup; Name=$FirewallName }
    $resourcesToCheck += @{ SubId=$SubscriptionId; RG=$FwVNetRG; Name=$FwVNetName }
    $resourcesToCheck += @{ SubId=$SubscriptionId; RG=$FwDataPipRG; Name=$FwDataPipName }
    if ($FwMgmtPipName) {
        $resourcesToCheck += @{ SubId=$SubscriptionId; RG=$FwMgmtPipRG; Name=$FwMgmtPipName }
    }
    $resourcesToCheck += $VNetList
    $resourcesToCheck += $RouteTableList
    
    Write-Log "Calling Test-ResourceLocks with $($resourceGroupsToCheck.Count) RGs and $($resourcesToCheck.Count) resources" -Level INFO
    
    $hasLocks = $false
    try {
        # Capture the function output
        $functionOutput = Test-ResourceLocks -ResourceGroups $resourceGroupsToCheck -Resources $resourcesToCheck
        
        # The actual return value should be a boolean - check if it's true
        if ($functionOutput -is [array]) {
            # If it's an array, the last item should be the actual return value
            $hasLocks = $functionOutput[-1] -eq $true
        } elseif ($functionOutput -is [string]) {
            # If it's a string, check if it contains "False" at the end
            $hasLocks = -not ($functionOutput -like "*False*")
        } else {
            # It should be a boolean
            $hasLocks = $functionOutput -eq $true
        }
        
        Write-Log "Lock check completed. Has locks: $hasLocks" -Level INFO
    } catch {
        Write-Log "Exception in Test-ResourceLocks: $($_.Exception.Message)" -Level ERROR
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
        $hasLocks = $false
    }
    
    if ($hasLocks) {
        if (-not $ForceContinueWithLocks) {
            Write-Log "=== OPERATION ABORTED DUE TO RESOURCE LOCKS ===" -Level ERROR
            Write-Log "Resource locks prevent safe modification of firewall and network resources." -Level ERROR
            Write-Log "To resolve this issue, remove the locks and re-run the runbook." -Level ERROR
            
            if ($isAzureAutomation) {
                throw "Resource locks detected. Cannot continue safely."
            } else {
                Write-Log "Exiting with error code 1" -Level INFO
                exit 1
            }
        } else {
            Write-Log "WARNING: ForceContinueWithLocks is enabled - continuing despite locks" -Level WARNING
            Write-Log "Operations may fail or produce unexpected results" -Level WARNING
            
            if (-not $isAzureAutomation) {
                $continue = Read-Host "Are you sure you want to continue with locks present? (Y/N)"
                if ($continue -ne 'Y') {
                    Write-Log "Operation cancelled by user" -Level WARNING
                    exit 0
                }
            }
        }
    }
    
    # === RETRIEVE FIREWALL ===
    Write-Log "=== RETRIEVING FIREWALL ===" -Level INFO
    $firewall = Get-AzFirewall -ResourceGroupName $FirewallResourceGroup -Name $FirewallName -ErrorAction Stop
    
    # Validate region
    if (-not (In-TargetRegion $firewall)) {
        throw "Firewall $FirewallName is in region $($firewall.Location), expected $FirewallRegion"
    }
    
    # Check if Virtual WAN firewall (not supported)
    if ($firewall.VirtualHub) {
        throw "This script supports VNet-based Azure Firewall only (Virtual WAN firewall detected)"
    }
    
    Write-Log "Firewall found and validated" -Level SUCCESS
    
    # === RESOLVE ALLOCATION RESOURCES ===
    Write-Log "=== RESOLVING ALLOCATION RESOURCES ===" -Level INFO
    
    # Validate required parameters
    if ([string]::IsNullOrWhiteSpace($FwVNetRG) -or [string]::IsNullOrWhiteSpace($FwVNetName)) {
        throw "VNet configuration missing. Please provide FwVNetRG and FwVNetName"
    }
    if ([string]::IsNullOrWhiteSpace($FwDataPipName)) {
        throw "Data Public IP name missing. Please provide FwDataPipName"
    }
    
    # Get VNet
    Write-Log "Retrieving VNet $FwVNetName from RG $FwVNetRG" -Level INFO
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $FwVNetRG -Name $FwVNetName -ErrorAction Stop
    Write-Log "  VNet retrieved successfully" -Level SUCCESS
    
    # Get Data Public IP
    Write-Log "Retrieving Data Public IP $FwDataPipName from RG $FwDataPipRG" -Level INFO
    $dataPip = Get-AzPublicIpAddress -ResourceGroupName $FwDataPipRG -Name $FwDataPipName -ErrorAction Stop
    Write-Log "  Data PIP retrieved: $($dataPip.IpAddress)" -Level SUCCESS
    
    # Get Management Public IP (optional)
    $mgmtPip = $null
    if ($FwMgmtPipName) {
        Write-Log "Retrieving Management Public IP $FwMgmtPipName from RG $FwMgmtPipRG" -Level INFO
        try {
            $mgmtPip = Get-AzPublicIpAddress -ResourceGroupName $FwMgmtPipRG -Name $FwMgmtPipName -ErrorAction Stop
            Write-Log "  Management PIP retrieved: $($mgmtPip.IpAddress)" -Level SUCCESS
        } catch {
            throw "Management PIP $FwMgmtPipName not found in RG $FwMgmtPipRG"
        }
    }
    
    # === CHECK ALLOCATION STATUS ===
    Write-Log "=== CHECKING FIREWALL ALLOCATION STATUS ===" -Level INFO
    
    # Check current allocation state - using same safe pattern as original
    $ipConfigCount = 0
    if ($firewall.IpConfigurations) {
        $ipConfigCount = $firewall.IpConfigurations.Count
    }
    
    $hasFirewallState = $firewall.PSObject.Properties.Name -contains 'FirewallState'
    $isStopped = $hasFirewallState -and ($firewall.FirewallState -eq 'Stopped')
    $isDeallocated = $ipConfigCount -eq 0
    
    Write-Log "Current status:" -Level INFO
    Write-Log "  IP Configuration Count: $ipConfigCount" -Level INFO
    Write-Log "  Firewall State: $(if($hasFirewallState){$firewall.FirewallState}else{'N/A'})" -Level INFO
    Write-Log "  Provisioning State: $($firewall.ProvisioningState)" -Level INFO
    Write-Log "  Needs Allocation: $(if($isDeallocated -or $isStopped){'Yes'}else{'No'})" -Level INFO
    
    # === ALLOCATE FIREWALL IF NEEDED ===
    if ($isDeallocated -or $isStopped) {
        if ($WhatIfMode) {
            $mgmtText = if ($mgmtPip) { $mgmtPip.Name } else { "none" }
            Write-Log "WHATIF: Would allocate firewall with:" -Level WARNING
            Write-Log "  VNet: $($vnet.Name)" -Level WARNING
            Write-Log "  Subnet: $FwSubnetName" -Level WARNING
            Write-Log "  Data PIP: $($dataPip.Name)" -Level WARNING
            Write-Log "  Management PIP: $mgmtText" -Level WARNING
        } else {
            Write-Log "=== ALLOCATING FIREWALL ===" -Level INFO
            Write-Log "This will assign IP configurations and start billing for compute resources" -Level INFO
            
            try {
                if ($mgmtPip) {
                    Write-Log "Allocating with Data and Management PIPs..." -Level INFO
                    $firewall.Allocate($vnet, $dataPip, $mgmtPip)
                } else {
                    Write-Log "Allocating with Data PIP only..." -Level INFO
                    $firewall.Allocate($vnet, $dataPip)
                }
                
                Write-Log "Applying allocation changes..." -Level INFO
                $firewall | Set-AzFirewall | Out-Null
                Write-Log "Allocation request submitted successfully" -Level SUCCESS
                
            } catch {
                Write-Log "Failed to allocate firewall: $($_.Exception.Message)" -Level ERROR
                Get-FirewallDiagnostics -ResourceGroup $FirewallResourceGroup -Name $FirewallName
                throw
            }
        }
    } else {
        Write-Log "Firewall already allocated (has IP configurations) - skipping allocation" -Level INFO
    }
    
    # === WAIT FOR FIREWALL AND GET IP ===
    $firewallIp = $null
    
    if ($WhatIfMode) {
        $firewallIp = "placeholder-IP"
        Write-Log "WHATIF: Would wait for firewall IP allocation" -Level WARNING
        Write-Log "WHATIF: Firewall IP would be: $firewallIp" -Level WARNING
    } else {
        Write-Log "=== ENSURING FIREWALL HAS IP ===" -Level INFO
        
        # Since the firewall object already shows it has IpConfigurations in the earlier check,
        # let's try to get the IP directly from the existing firewall object first
        $existingIp = $null
        try {
            if ($firewall.IpConfigurations) {
                if ($firewall.IpConfigurations.Count -gt 0) {
                    $existingIp = ($firewall.IpConfigurations | Select-Object -First 1).PrivateIPAddress
                }
            }
        } catch {
            Write-Log "Could not get IP from existing object, will refresh" -Level INFO
        }
        
        if ($existingIp) {
            Write-Log "Using existing firewall IP: $existingIp" -Level SUCCESS
            $firewallIp = $existingIp
        } else {
            # Need to wait or refresh to get IP
            try {
                $readyFirewall, $rawIp = Wait-FirewallReady `
                    -ResourceGroup $FirewallResourceGroup `
                    -Name $FirewallName `
                    -TimeoutMinutes $WaitTimeoutMinutes `
                    -PollSeconds $PollIntervalSeconds
                
                # Resolve and validate the IP
                $firewallIp = Resolve-FirewallPrivateIp -FirewallObject $readyFirewall -CandidateIp $rawIp
            } catch {
                Write-Log "Error during wait: $($_.Exception.Message)" -Level WARNING
                
                # Last resort - try to get firewall again and extract IP
                try {
                    Write-Log "Attempting to retrieve firewall state directly..." -Level INFO
                    $fw = Get-AzFirewall -ResourceGroupName $FirewallResourceGroup -Name $FirewallName -ErrorAction Stop
                    if ($fw.IpConfigurations) {
                        if ($fw.IpConfigurations.Count -gt 0) {
                            $firewallIp = ($fw.IpConfigurations | Select-Object -First 1).PrivateIPAddress
                        }
                    }
                } catch {
                    Write-Log "Final attempt failed: $($_.Exception.Message)" -Level ERROR
                    throw "Unable to determine firewall IP address"
                }
            }
        }
        
        if (-not $firewallIp) {
            throw "Failed to resolve valid IPv4 address for firewall"
        }
        
        Write-Log "Firewall IP confirmed: $firewallIp" -Level SUCCESS
    }
    
    # === UPDATE DNS SERVERS ===
    if ($DnsMode -ne "Skip") {
        Write-Log "=== UPDATING VNET DNS SERVERS ===" -Level INFO
        Write-Log "DNS Mode: $DnsMode" -Level INFO
        
        foreach ($vnetDef in $VNetList) {
            Update-VNetDns -VNetDefinition $vnetDef -FirewallIp $firewallIp -Mode $DnsMode
        }
        
        Write-Log "DNS updates completed" -Level SUCCESS
    } else {
        Write-Log "Skipping DNS updates (DnsMode: Skip)" -Level INFO
    }
    
    # === UPDATE ROUTE TABLES ===
    Write-Log "=== UPDATING ROUTE TABLES ===" -Level INFO
    
    foreach ($rtDef in $RouteTableList) {
        Update-RouteTable -RouteTableDefinition $rtDef -FirewallIp $firewallIp
    }
    
    Write-Log "Route table updates completed" -Level SUCCESS
    
    # === FINAL SUMMARY ===
    Write-Log "=== OPERATION COMPLETED SUCCESSFULLY ===" -Level SUCCESS
    Write-Log "Firewall Status: Allocated and Running" -Level SUCCESS
    Write-Log "Firewall Private IP: $firewallIp" -Level SUCCESS
    Write-Log "DNS Servers Updated: $($VNetList.Count) VNets" -Level INFO
    Write-Log "Route Tables Updated: $($RouteTableList.Count) Route Tables" -Level INFO
    
} catch {
    Write-Log "OPERATION FAILED: $($_.Exception.Message)" -Level ERROR
    
    # Try to get current state for debugging
    try {
        # Ensure we're in the correct subscription before getting diagnostics
        Use-Subscription -SubscriptionId $SubscriptionId
        Get-FirewallDiagnostics -ResourceGroup $FirewallResourceGroup -Name $FirewallName
    } catch {
        Write-Log "Could not retrieve firewall diagnostics: $($_.Exception.Message)" -Level INFO
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