#Requires -Version 7.0
<#
.SYNOPSIS
    Copies Azure Firewall Policy settings and Rule Collection Groups from source to target.

.DESCRIPTION
    - Comprehensive policy settings copy (DNS, Threat Intel, Insights, SNAT, IDS, TLS, etc.)
    - Rule Collection Groups copied via REST API for reliability
    - Works with ACTIVE firewalls (takes ~6-7 minutes per RCG)
    - Much faster with firewall powered OFF (~1 minute per RCG)
    - Enhanced resource lock detection with multiple methods
    - STOPS execution if resource locks are detected (unless forced)

.NOTES
    Version : 1.4.0
    Author  : Aaron Bhatti
    Date    : 2025-08-12
    
    Changes:
    - v1.4.0: Modified to stop execution when resource locks are detected
    - v1.3.0: Enhanced resource lock detection with multiple detection methods
    - v1.2.0: Improved resource lock detection clarity and removed source lock checking

#>

# ============= CONFIGURATION =============
$TenantId = "3ec094fc-4da6-40af-8073-0303aaa9c094"
$SubscriptionId = "c7f53b68-70fa-458f-9976-95d722f3312f"

# Source Policy (PROD)
$SourceResourceGroup = "rg-prod-network-uks-hub"
$SourcePolicyName = "fwpol-prod-hub-uks"

# Target Policy (DR)
$TargetResourceGroup = "rg-dr-network-ukw-hub"
$TargetPolicyName = "fwpol-dr-hub-ukw"

# Operation Settings
$WhatIfMode = $false
$ForceContinueWithLocks = $false  # Set to $true to continue despite locks (not recommended)

# Enhanced Settings for Active Firewalls
$MaxRetries = 3                     # Maximum retry attempts for failed API calls
$InitialRetryDelaySeconds = 10      # Initial retry delay for failed calls
$MaxWaitForOperationSeconds = 1800  # 30 minutes max wait for async operations
$MaxWaitForPolicySeconds = 600      # 10 minutes max wait for policy ready state
$MinDelayBetweenRCGSeconds = 5      # Minimum delay between RCG operations
$BatchSize = 10                     # Number of RCGs to process before checking overall health
$PollIntervalSeconds = 5            # How often to poll for operation status
# =========================================

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Check if running in Azure Automation
$isAzureAutomation = $null -ne $env:AUTOMATION_ASSET_ACCOUNTID

# Initialize transcript (local only)
if (-not $isAzureAutomation) {
    $transcriptPath = Join-Path $env:TEMP "AzFirewallPolicyCopy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Start-Transcript -Path $transcriptPath -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    
    if ($isAzureAutomation) {
        # In Azure Automation, use Write-Output for all messages to avoid error stream pollution
        switch ($Level) {
            'ERROR'   { 
                # Use Write-Output with [ERROR] prefix instead of Write-Error to avoid stack trace noise
                Write-Output "[ERROR] $logMessage" 
            }
            'WARNING' { 
                # Keep Write-Warning as it doesn't cause the same issues
                Write-Warning -Message $logMessage 
            }
            'SUCCESS' { 
                Write-Output "[SUCCESS] $logMessage" 
            }
            default   { 
                Write-Output "[INFO] $logMessage" 
            }
        }
    } else {
        # For local execution, use colored output
        $colorMessage = "[$Level] $logMessage"
        switch ($Level) {
            'ERROR'   { Write-Host $colorMessage -ForegroundColor Red }
            'WARNING' { Write-Host $colorMessage -ForegroundColor Yellow }
            'SUCCESS' { Write-Host $colorMessage -ForegroundColor Green }
            default   { Write-Host $colorMessage }
        }
    }
}

function Wait-PolicyReady {
    param(
        [string]$ResourceGroup,
        [string]$PolicyName,
        [int]$MaxWaitSeconds = 600,
        [int]$CheckIntervalSeconds = 5,
        [switch]$QuickCheck  # For a quick single check without extended waiting
    )
    
    if ($QuickCheck) {
        try {
            $policy = Get-AzFirewallPolicy -ResourceGroupName $ResourceGroup -Name $PolicyName -ErrorAction Stop
            return ($policy.ProvisioningState -eq 'Succeeded')
        } catch {
            return $false
        }
    }
    
    Write-Log "Waiting for policy '$PolicyName' to be ready (max wait: ${MaxWaitSeconds}s)..." -Level INFO
    $startTime = Get-Date
    $lastState = ""
    $checkInterval = 2  # Start with quick checks
    
    do {
        try {
            $policy = Get-AzFirewallPolicy -ResourceGroupName $ResourceGroup -Name $PolicyName -ErrorAction Stop
            $state = $policy.ProvisioningState
            
            if ($state -ne $lastState) {
                $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                Write-Log "  Policy state: $state (${elapsed}s elapsed)" -Level INFO
                $lastState = $state
            }
            
            if ($state -eq 'Succeeded') {
                $duration = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                Write-Log "  Policy ready after ${duration}s" -Level SUCCESS
                return $true
            }
            
            if ($state -eq 'Failed') {
                Write-Log "  Policy in failed state" -Level ERROR
                return $false
            }
            
            # Gradually increase check interval up to maximum
            if ($checkInterval -lt $CheckIntervalSeconds) {
                $checkInterval = [Math]::Min($checkInterval + 1, $CheckIntervalSeconds)
            }
            
            Start-Sleep -Seconds $checkInterval
            
            if (((Get-Date) - $startTime).TotalSeconds -gt $MaxWaitSeconds) {
                Write-Log "  Timeout waiting for policy (waited ${MaxWaitSeconds}s)" -Level WARNING
                return $false
            }
        } catch {
            Write-Log "  Error checking policy state: $($_.Exception.Message)" -Level WARNING
            Start-Sleep -Seconds $CheckIntervalSeconds
            
            # Check timeout even on error
            if (((Get-Date) - $startTime).TotalSeconds -gt $MaxWaitSeconds) {
                Write-Log "  Timeout waiting for policy" -Level WARNING
                return $false
            }
        }
    } while ($true)
}

function Wait-ForAsyncOperation {
    param(
        [string]$OperationUri,
        [hashtable]$Headers,
        [int]$MaxWaitSeconds = 1800,  # 30 minutes default
        [int]$PollIntervalSeconds = 5
    )
    
    $startTime = Get-Date
    $lastStatus = ""
    
    Write-Log "    Monitoring async operation..." -Level INFO
    
    while ($true) {
        try {
            $operationResult = Invoke-RestMethod -Method GET -Uri $OperationUri -Headers $Headers -ErrorAction Stop
            $status = $operationResult.status
            
            if ($status -ne $lastStatus) {
                $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                Write-Log "      Operation status: $status (${elapsed}s elapsed)" -Level INFO
                $lastStatus = $status
            }
            
            switch ($status) {
                'Succeeded' {
                    $totalTime = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                    Write-Log "      Operation completed successfully in ${totalTime}s" -Level SUCCESS
                    return $true
                }
                'Failed' {
                    $errorMessage = if ($operationResult.error) { $operationResult.error.message } else { "Unknown error" }
                    Write-Log "      Operation failed: $errorMessage" -Level ERROR
                    return $false
                }
                'Canceled' {
                    Write-Log "      Operation was canceled" -Level WARNING
                    return $false
                }
                { $_ -in 'InProgress', 'Running', 'Pending', 'Updating' } {
                    # Continue polling - added 'Updating' as valid status
                }
                default {
                    # Unknown status - log but continue
                    Write-Log "      Unknown operation status: $status (continuing)" -Level WARNING
                }
            }
            
            # Check timeout
            if (((Get-Date) - $startTime).TotalSeconds -gt $MaxWaitSeconds) {
                Write-Log "      Operation timeout after ${MaxWaitSeconds}s" -Level ERROR
                return $false
            }
            
            Start-Sleep -Seconds $PollIntervalSeconds
            
        } catch {
            Write-Log "      Error checking operation status: $($_.Exception.Message)" -Level WARNING
            
            # Check if we've exceeded timeout
            if (((Get-Date) - $startTime).TotalSeconds -gt $MaxWaitSeconds) {
                Write-Log "      Operation monitoring timeout" -Level ERROR
                return $false
            }
            
            Start-Sleep -Seconds $PollIntervalSeconds
        }
    }
}

function Invoke-AzureRestWithRetry {
    param(
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers,
        [string]$Body = $null,
        [int]$MaxRetries = 3,
        [int]$InitialRetryDelay = 10,
        [int]$MaxOperationWaitSeconds = 1800  # 30 minutes for async operations
    )
    
    $retryCount = 0
    $delay = $InitialRetryDelay
    
    while ($retryCount -le $MaxRetries) {
        try {
            $params = @{
                Method = $Method
                Uri = $Uri
                Headers = $Headers
                ErrorAction = 'Stop'
            }
            
            if ($Body) {
                $params['Body'] = $Body
                $params['ContentType'] = 'application/json'
            }
            
            $response = Invoke-WebRequest @params
            
            # Check for accepted status (202) which means long-running operation
            if ($response.StatusCode -eq 202) {
                Write-Log "  Operation accepted (202), checking for async operation headers..." -Level INFO
                
                # Check for Azure-AsyncOperation or Location header
                $asyncOperationUri = $null
                
                # Try different header access methods
                if ($response.Headers) {
                    if ($response.Headers.ContainsKey('Azure-AsyncOperation')) {
                        $asyncOperationUri = $response.Headers['Azure-AsyncOperation']
                        if ($asyncOperationUri -is [array]) {
                            $asyncOperationUri = $asyncOperationUri[0]
                        }
                        Write-Log "    Found Azure-AsyncOperation header" -Level INFO
                    } elseif ($response.Headers.ContainsKey('Location')) {
                        $asyncOperationUri = $response.Headers['Location']
                        if ($asyncOperationUri -is [array]) {
                            $asyncOperationUri = $asyncOperationUri[0]
                        }
                        Write-Log "    Found Location header" -Level INFO
                    }
                }
                
                if ($asyncOperationUri) {
                    Write-Log "    Monitoring operation at: $asyncOperationUri" -Level INFO
                    # Wait for async operation to complete - this has its own timeout
                    $asyncResult = Wait-ForAsyncOperation -OperationUri $asyncOperationUri -Headers $Headers -MaxWaitSeconds $MaxOperationWaitSeconds
                    if (-not $asyncResult) {
                        throw "Async operation failed or timed out after ${MaxOperationWaitSeconds}s"
                    }
                } else {
                    Write-Log "    No async operation header found, operation may complete synchronously" -Level INFO
                }
            }
            
            return $response
            
        } catch {
            $errorDetails = $_.Exception.Message
            $statusCode = $null
            
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }
            
            # Don't retry if it was an async operation timeout
            if ($errorDetails -like "*Async operation failed or timed out*") {
                Write-Log "  Async operation timeout - not retrying" -Level ERROR
                throw
            }
            
            Write-Log "  API call failed (Attempt $($retryCount + 1)/$($MaxRetries + 1))" -Level WARNING
            
            if ($statusCode) {
                Write-Log "    Status: $statusCode" -Level WARNING
                
                if ($statusCode -eq 400) {
                    # Bad Request - might be due to policy being updated
                    Write-Log "    Bad Request (400) - Policy might be updating" -Level WARNING
                    $delay = [Math]::Min($delay * 2, 120)  # Cap at 2 minutes
                } elseif ($statusCode -eq 409) {
                    # Conflict - resource is being modified
                    Write-Log "    Conflict (409) - Resource busy (likely locked)" -Level WARNING
                    Write-Log "    This is expected if resource locks are present" -Level INFO
                    $delay = [Math]::Min($delay * 1.5, 90)
                } elseif ($statusCode -eq 429) {
                    # Too Many Requests - throttling
                    Write-Log "    Throttled (429) - Slowing down" -Level WARNING
                    $delay = [Math]::Min($delay * 3, 180)  # Cap at 3 minutes
                }
            }
            
            Write-Log "    Error: $errorDetails" -Level WARNING
            
            if ($retryCount -eq $MaxRetries) {
                Write-Log "  Maximum retries exceeded for API call" -Level ERROR
                throw
            }
            
            Write-Log "    Waiting ${delay}s before retry..." -Level INFO
            Start-Sleep -Seconds $delay
            $retryCount++
        }
    }
}

function Test-FirewallActive {
    param(
        [string]$ResourceGroup,
        [string]$PolicyName
    )
    
    try {
        # Check if any firewalls are using this policy
        $firewalls = Get-AzFirewall -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
        if (-not $firewalls) {
            return $false
        }
        
        foreach ($fw in $firewalls) {
            if ($fw.FirewallPolicy -and $fw.FirewallPolicy.Id -like "*$PolicyName*") {
                if ($fw.ProvisioningState -eq 'Succeeded' -and $fw.IpConfigurations -and $fw.IpConfigurations.Count -gt 0) {
                    Write-Log "Active firewall detected: $($fw.Name)" -Level WARNING
                    return $true
                }
            }
        }
    } catch {
        Write-Log "Could not check firewall status: $($_.Exception.Message)" -Level WARNING
    }
    
    return $false
}

# Track if we have locks for later reference
$script:HasTargetLocks = $false

try {
    $startTime = Get-Date
    Write-Log "=== AZURE FIREWALL POLICY COPY STARTED ===" -Level SUCCESS
    Write-Log "Source: $SourcePolicyName in $SourceResourceGroup" -Level INFO
    Write-Log "Target: $TargetPolicyName in $TargetResourceGroup" -Level INFO
    Write-Log "WhatIf Mode: $WhatIfMode" -Level INFO
    Write-Log "Force Continue With Locks: $ForceContinueWithLocks" -Level INFO

    # === AUTHENTICATION ===
    Write-Log "Authenticating to Azure..." -Level INFO
    if ($isAzureAutomation) {
        Connect-AzAccount -Identity -Tenant $TenantId -Subscription $SubscriptionId | Out-Null
        Write-Log "Connected using Managed Identity" -Level SUCCESS
    } else {
        $context = Get-AzContext
        if (-not $context) { 
            throw "Not connected to Azure. Please run Connect-AzAccount first." 
        }
        if ($context.Subscription.Id -ne $SubscriptionId) {
            Write-Log "Switching to subscription: $SubscriptionId" -Level INFO
            Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        }
        Write-Log "Using existing connection: $($context.Account.Id)" -Level INFO
    }

    # === CHECK FIREWALL STATUS ===
    $isFirewallActive = Test-FirewallActive -ResourceGroup $TargetResourceGroup -PolicyName $TargetPolicyName
    if ($isFirewallActive) {
        Write-Log "WARNING: Target firewall is ACTIVE - operations will take longer" -Level WARNING
        Write-Log "Consider powering off the firewall for faster operations" -Level WARNING
        $MaxWaitForPolicySeconds = 1800  # Increase to 30 minutes for active firewalls
    } else {
        Write-Log "Target firewall appears to be inactive - operations should be faster" -Level INFO
    }

    # === CHECK FOR RESOURCE LOCKS ON TARGET ONLY ===
    Write-Log "=== CHECKING FOR RESOURCE LOCKS ON TARGET ===" -Level INFO
    Write-Log "Checking locks on target resource group and policy only..." -Level INFO
    Write-Log "Target RG: $TargetResourceGroup" -Level INFO
    Write-Log "Target Policy: $TargetPolicyName" -Level INFO
    
    $allLocks = @()
    $locksFound = $false
    
    # Method 1: Check locks on target resource group
    Write-Log "  Checking target resource group for locks..." -Level INFO
    try {
        $rgLocks = @(Get-AzResourceLock -ResourceGroupName $TargetResourceGroup -ErrorAction Stop | 
                     Where-Object { 
                         # Ensure we only get locks for the target RG, not source
                         $_.ResourceId -notlike "*$SourceResourceGroup*" -and
                         ($_.ResourceId -like "*$TargetResourceGroup*" -or 
                          $_.ResourceType -eq 'Microsoft.Authorization/locks')
                     })
        if ($rgLocks.Count -gt 0) {
            Write-Log "    Found $($rgLocks.Count) lock(s) on target resource group" -Level INFO
            $allLocks += $rgLocks
            $locksFound = $true
        } else {
            Write-Log "    No locks found on target resource group" -Level INFO
        }
    } catch {
        $lockError = $_.Exception.Message
        Write-Log "    Could not check resource group locks: $lockError" -Level WARNING
        # Continue execution even if lock check fails
    }
    
    # Method 2: Check locks specifically on the target firewall policy
    Write-Log "  Checking target firewall policy for locks..." -Level INFO
    try {
        # Build the policy resource ID
        $policyResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$TargetResourceGroup/providers/Microsoft.Network/firewallPolicies/$TargetPolicyName"
        
        # Get all locks in the resource group first
        $allRgLocks = @(Get-AzResourceLock -ResourceGroupName $TargetResourceGroup -ErrorAction Stop)
        
        # Filter for locks on the firewall policy
        $policyLocks = @($allRgLocks | Where-Object { 
            $_.ResourceId -like "*firewallPolicies/$TargetPolicyName*" -or
            $_.ResourceId -eq $policyResourceId
        })
        
        if ($policyLocks.Count -gt 0) {
            Write-Log "    Found $($policyLocks.Count) lock(s) on target firewall policy" -Level INFO
            $allLocks += $policyLocks
            $locksFound = $true
        } else {
            Write-Log "    No locks found on target firewall policy" -Level INFO
        }
    } catch {
        $policyLockError = $_.Exception.Message
        Write-Log "    Could not check policy locks: $policyLockError" -Level WARNING
        # Continue execution even if lock check fails
    }
    
    # Method 3: Check for subscription-level locks that might affect the target RG
    Write-Log "  Checking for subscription-level locks affecting target..." -Level INFO
    try {
        # First check if we can access subscription-level locks
        $subScope = "/subscriptions/$SubscriptionId"
        $subLocks = $null
        
        try {
            $subLocks = @(Get-AzResourceLock -Scope $subScope -ErrorAction Stop)
        } catch {
            # If we can't check subscription locks, that's OK - continue
            Write-Log "    Cannot check subscription-level locks (may lack permissions)" -Level INFO
            $subLocks = @()
        }
        
        if ($subLocks -and $subLocks.Count -gt 0) {
            # Filter to only locks that could affect our target
            $relevantSubLocks = @($subLocks | Where-Object { 
                # Only include subscription locks that could affect our target
                $_.ResourceId -eq $subScope -or
                $_.ResourceId -like "*$TargetResourceGroup*"
            })
            
            if ($relevantSubLocks.Count -gt 0) {
                Write-Log "    Found $($relevantSubLocks.Count) subscription-level lock(s) that may affect target" -Level WARNING
                $allLocks += $relevantSubLocks
                $locksFound = $true
            } else {
                Write-Log "    No subscription-level locks affecting target found" -Level INFO
            }
        } else {
            Write-Log "    No subscription-level locks found" -Level INFO
        }
    } catch {
        $subLockError = $_.Exception.Message
        Write-Log "    Could not check subscription locks: $subLockError" -Level WARNING
        # Continue execution even if lock check fails
    }
    
    # Remove duplicates based on lock ID
    if ($allLocks.Count -gt 0) {
        $uniqueLocks = $allLocks | Group-Object -Property ResourceId | ForEach-Object { $_.Group[0] }
        $allLocks = @($uniqueLocks)
    }
    
    # Report findings
    if ($locksFound -and $allLocks.Count -gt 0) {
        Write-Log "=== ⚠️ RESOURCE LOCKS DETECTED ON TARGET ===" -Level ERROR
        Write-Log "Found $($allLocks.Count) lock(s) on target resources that will prevent proper operation:" -Level ERROR
        
        foreach ($lock in $allLocks) {
            Write-Log "  Lock Name: $($lock.Name)" -Level ERROR
            Write-Log "    Level: $($lock.Properties.level)" -Level ERROR
            Write-Log "    Scope: $($lock.ResourceId)" -Level INFO
            if ($lock.Properties.notes) {
                Write-Log "    Notes: $($lock.Properties.notes)" -Level INFO
            }
        }
        
        $script:HasTargetLocks = $true
        
        if (-not $ForceContinueWithLocks) {
            Write-Log "=== OPERATION ABORTED DUE TO RESOURCE LOCKS ===" -Level ERROR
            Write-Log "Resource locks on the target prevent the proper deletion of existing Rule Collection Groups." -Level ERROR
            Write-Log "This will cause the copy operation to fail or produce incomplete results." -Level ERROR
            Write-Log "To resolve this issue, remove the locks on target resources" -Level ERROR
            Write-Log "Exiting script due to resource locks on target." -Level ERROR
            
            # Exit with error code
            if ($isAzureAutomation) {
                # Set a flag to indicate this is an expected exit
                $global:ExpectedExit = $true
                throw "Resource locks detected on target resource group or policy. Cannot continue safely."
            } else {
                Write-Log "Exiting with error code 1" -Level INFO
                exit 1
            }
        } else {
            Write-Log "WARNING: ForceContinueWithLocks is enabled - continuing despite locks" -Level WARNING
            Write-Log "Expect 409 Conflict errors during the deletion phase" -Level WARNING
            
            if (-not $isAzureAutomation) {
                $continue = Read-Host "Are you sure you want to continue with locks present? (Y/N)"
                if ($continue -ne 'Y') {
                    Write-Log "Operation cancelled by user" -Level WARNING
                    exit 0
                }
            }
        }
    } else {
        Write-Log "=== ✅ NO RESOURCE LOCKS DETECTED ON TARGET ===" -Level SUCCESS
        Write-Log "No locks found on target resource group: $TargetResourceGroup" -Level SUCCESS
        Write-Log "No locks found on target policy: $TargetPolicyName" -Level SUCCESS
        Write-Log "Note: If you still see 409 errors, possible causes:" -Level INFO
        Write-Log "  - Policy is attached to an active firewall" -Level INFO
        Write-Log "  - Another operation is in progress" -Level INFO
        Write-Log "  - Hidden locks or permission issues" -Level INFO
        Write-Log "  - Azure Resource Manager timing issues" -Level INFO
        $script:HasTargetLocks = $false
    }
    
    Write-Log "=== TARGET LOCK CHECK COMPLETE ===" -Level INFO

    # === GET POLICIES ===
    Write-Log "Loading policies..." -Level INFO
    
    $sourcePolicy = Get-AzFirewallPolicy -ResourceGroupName $SourceResourceGroup -Name $SourcePolicyName -ErrorAction Stop
    if (-not $sourcePolicy) {
        throw "Source policy not found: $SourcePolicyName"
    }
    
    $targetPolicy = Get-AzFirewallPolicy -ResourceGroupName $TargetResourceGroup -Name $TargetPolicyName -ErrorAction Stop
    if (-not $targetPolicy) {
        throw "Target policy not found: $TargetPolicyName"
    }
    
    Write-Log "Policies loaded successfully" -Level SUCCESS

    # === COPY POLICY SETTINGS ===
    if ($WhatIfMode) {
        Write-Log "WHATIF: Would copy policy settings" -Level WARNING
    } else {
        Write-Log "Copying policy-level settings..." -Level INFO
        
        # Build comprehensive update parameters
        $updateParams = @{
            ResourceGroupName = $TargetResourceGroup
            Name = $TargetPolicyName
            Location = $targetPolicy.Location
        }
        
        # Copy all available policy settings
        if ($sourcePolicy.ThreatIntelMode) { 
            $updateParams['ThreatIntelMode'] = $sourcePolicy.ThreatIntelMode
            Write-Log "  Threat Intel Mode: $($sourcePolicy.ThreatIntelMode)" -Level INFO
        }
        
        if ($sourcePolicy.ThreatIntelWhitelist) { 
            $updateParams['ThreatIntelWhitelist'] = $sourcePolicy.ThreatIntelWhitelist 
        }
        
        if ($sourcePolicy.Sku) { 
            $updateParams['SkuTier'] = $sourcePolicy.Sku.Tier
            Write-Log "  SKU Tier: $($sourcePolicy.Sku.Tier)" -Level INFO
        }
        
        # Advanced settings - check if properties exist before accessing
        if ($sourcePolicy.PSObject.Properties.Name -contains 'Insights' -and $sourcePolicy.Insights) { 
            $updateParams['Insights'] = $sourcePolicy.Insights 
            Write-Log "  Insights configured" -Level INFO
        }
        
        if ($sourcePolicy.PSObject.Properties.Name -contains 'ExplicitProxy' -and $sourcePolicy.ExplicitProxy) { 
            $updateParams['ExplicitProxy'] = $sourcePolicy.ExplicitProxy 
            Write-Log "  Explicit Proxy configured" -Level INFO
        }
        
        if ($sourcePolicy.PSObject.Properties.Name -contains 'Snat' -and $sourcePolicy.Snat) { 
            $updateParams['Snat'] = $sourcePolicy.Snat 
            Write-Log "  SNAT configured" -Level INFO
        }
        
        if ($sourcePolicy.PSObject.Properties.Name -contains 'IntrusionDetection' -and $sourcePolicy.IntrusionDetection) { 
            $updateParams['IntrusionDetection'] = $sourcePolicy.IntrusionDetection 
            Write-Log "  Intrusion Detection configured" -Level INFO
        }
        
        if ($sourcePolicy.PSObject.Properties.Name -contains 'TransportSecurity' -and $sourcePolicy.TransportSecurity) { 
            $updateParams['TransportSecurity'] = $sourcePolicy.TransportSecurity 
            Write-Log "  Transport Security configured" -Level INFO
        }
        
        if ($sourcePolicy.PSObject.Properties.Name -contains 'PrivateRange' -and $sourcePolicy.PrivateRange) { 
            $updateParams['PrivateRange'] = $sourcePolicy.PrivateRange 
            Write-Log "  Private Range configured" -Level INFO
        }
        
        if ($sourcePolicy.PSObject.Properties.Name -contains 'SqlSetting' -and $sourcePolicy.SqlSetting) { 
            $updateParams['SqlSetting'] = $sourcePolicy.SqlSetting 
            Write-Log "  SQL Setting configured" -Level INFO
        }
        
        # DNS Settings (special handling)
        if ($sourcePolicy.DnsSettings) {
            $dnsSettings = New-Object Microsoft.Azure.Commands.Network.Models.PSAzureFirewallPolicyDnsSettings
            $serversList = New-Object 'System.Collections.Generic.List[System.String]'
            foreach ($server in $sourcePolicy.DnsSettings.Servers) { 
                $serversList.Add($server.ToString()) 
            }
            $dnsSettings.Servers = $serversList
            $dnsSettings.EnableProxy = $sourcePolicy.DnsSettings.EnableProxy
            $updateParams['DnsSetting'] = $dnsSettings
            Write-Log "  DNS Servers: [$($serversList -join ', ')]" -Level INFO
            Write-Log "  DNS Proxy: $($dnsSettings.EnableProxy)" -Level INFO
        }
        
        # Apply all settings with retry logic
        $retryCount = 0
        $maxRetries = 3
        $updateSuccess = $false
        
        while ($retryCount -lt $maxRetries -and -not $updateSuccess) {
            try {
                Set-AzFirewallPolicy @updateParams -ErrorAction Stop | Out-Null
                Write-Log "Policy settings applied successfully" -Level SUCCESS
                $updateSuccess = $true
            } catch {
                $retryCount++
                $errorMsg = $_.Exception.Message
                if ($retryCount -ge $maxRetries) {
                    throw "Failed to update policy settings after $maxRetries attempts: $errorMsg"
                }
                Write-Log ("Failed to update policy settings, retry " + $retryCount + "/" + $maxRetries + ": " + $errorMsg) -Level WARNING
                Start-Sleep -Seconds (30 * $retryCount)
            }
        }
        
        # Wait for policy to be ready
        $policyReady = Wait-PolicyReady -ResourceGroup $TargetResourceGroup -PolicyName $TargetPolicyName -MaxWaitSeconds $MaxWaitForPolicySeconds
        if (-not $policyReady) {
            Write-Log "Policy did not become ready after settings update, but continuing..." -Level WARNING
        }
    }

    # === COPY RULE COLLECTION GROUPS ===
    Write-Log "=== COPYING RULE COLLECTION GROUPS ===" -Level INFO
    
    # Get access token with retry
    $token = $null
    $tokenRetries = 0
    while ($tokenRetries -lt 3 -and -not $token) {
        try {
            $token = (Get-AzAccessToken -ResourceUrl 'https://management.azure.com/').Token
            if (-not $token) {
                throw "Token is null or empty"
            }
        } catch {
            $tokenRetries++
            $tokenError = $_.Exception.Message
            Write-Log ("Failed to get access token, retry " + $tokenRetries + "/3: " + $tokenError) -Level WARNING
            if ($tokenRetries -lt 3) {
                Start-Sleep -Seconds 5
            }
        }
    }
    
    if (-not $token) {
        throw "Failed to obtain access token after 3 attempts"
    }
    
    $headers = @{ 
        'Authorization' = "Bearer $token"
        'Content-Type' = 'application/json'
    }
    $apiVersion = '2024-03-01'  # Latest stable API version for firewall policies
    
    # Get source RCGs
    $srcUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$SourceResourceGroup/providers/Microsoft.Network/firewallPolicies/$SourcePolicyName/ruleCollectionGroups?api-version=$apiVersion"
    
    try {
        $sourceRcgsResponse = Invoke-RestMethod -Method GET -Uri $srcUri -Headers $headers -ErrorAction Stop
        $sourceRcgs = $sourceRcgsResponse.value
    } catch {
        $srcError = $_.Exception.Message
        Write-Log "Failed to get source RCGs: $srcError" -Level ERROR
        $sourceRcgs = @()
    }
    
    if ($sourceRcgs -and $sourceRcgs.Count -gt 0) {
        Write-Log "Found $($sourceRcgs.Count) source RCG(s)" -Level INFO
        foreach ($rcg in $sourceRcgs) {
            Write-Log "  - $($rcg.name) (Priority: $($rcg.properties.priority))" -Level INFO
        }
    } else {
        Write-Log "No RCGs found in source policy" -Level WARNING
    }
    
    if (-not $WhatIfMode -and $sourceRcgs -and $sourceRcgs.Count -gt 0) {
        # Get and delete existing target RCGs
        $tgtListUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$TargetResourceGroup/providers/Microsoft.Network/firewallPolicies/$TargetPolicyName/ruleCollectionGroups?api-version=$apiVersion"
        $targetRcgs = @()
        
        try { 
            $targetRcgsResponse = Invoke-RestMethod -Method GET -Uri $tgtListUri -Headers $headers -ErrorAction Stop
            $targetRcgs = $targetRcgsResponse.value
        } catch {
            $tgtError = $_.Exception.Message
            Write-Log "No existing RCGs in target or error retrieving: $tgtError" -Level INFO
        }
        
        if ($targetRcgs -and $targetRcgs.Count -gt 0) {
            if ($script:HasTargetLocks) {
                Write-Log "Resource locks detected - deletion will fail with 409 errors (this is expected)" -Level WARNING
            }
            
            Write-Log "Attempting to remove $($targetRcgs.Count) existing target RCG(s)..." -Level INFO
            Write-Log "Note: 409 errors during deletion are expected and harmless" -Level INFO
            $deleteCount = 0
            
            foreach ($rcg in $targetRcgs) {
                $deleteCount++
                Write-Log "  [$deleteCount/$($targetRcgs.Count)] Removing: $($rcg.name)" -Level INFO
                $deleteUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$TargetResourceGroup/providers/Microsoft.Network/firewallPolicies/$TargetPolicyName/ruleCollectionGroups/$($rcg.name)?api-version=$apiVersion"
                
                try {
                    $deleteResponse = Invoke-AzureRestWithRetry `
                        -Method DELETE `
                        -Uri $deleteUri `
                        -Headers $headers `
                        -MaxRetries $MaxRetries `
                        -InitialRetryDelay $InitialRetryDelaySeconds
                    
                    # Wait for deletion to complete
                    $deleteReady = Wait-PolicyReady -ResourceGroup $TargetResourceGroup -PolicyName $TargetPolicyName -MaxWaitSeconds $MaxWaitForPolicySeconds
                    if (-not $deleteReady) {
                        Write-Log "    Policy not ready after delete, but continuing..." -Level WARNING
                    }
                    
                    # Additional delay if firewall is active
                    if ($isFirewallActive -and $deleteCount -lt $targetRcgs.Count) {
                        Write-Log "    Waiting ${MinDelayBetweenRCGSeconds}s before next operation..." -Level INFO
                        Start-Sleep -Seconds $MinDelayBetweenRCGSeconds
                    }
                } catch {
                    $deleteError = $_.Exception.Message
                    if ($deleteError -like "*409*" -or $deleteError -like "*Conflict*") {
                        Write-Log "    Expected: Could not delete due to conflict - will overwrite instead" -Level INFO
                    } else {
                        Write-Log "    Could not delete RCG: $deleteError" -Level WARNING
                    }
                }
            }
        }
        
        # Copy source RCGs to target with intelligent monitoring
        if ($sourceRcgs -and $sourceRcgs.Count -gt 0) {
            $count = 0
            $batchCount = 0
            $failedRcgs = @()
            $successCount = 0
            
            foreach ($rcg in $sourceRcgs) {
                $count++
                $batchCount++
                $rcgName = $rcg.name
                
                Write-Log "[$count/$($sourceRcgs.Count)] Copying RCG: $rcgName" -Level INFO
                Write-Log "  Priority: $($rcg.properties.priority), Collections: $($rcg.properties.ruleCollections.Count)" -Level INFO
                
                # Check if policy is ready before attempting
                $policyReady = Wait-PolicyReady -ResourceGroup $TargetResourceGroup -PolicyName $TargetPolicyName -QuickCheck
                if (-not $policyReady) {
                    Write-Log "  Policy not ready, waiting..." -Level INFO
                    $waitResult = Wait-PolicyReady -ResourceGroup $TargetResourceGroup -PolicyName $TargetPolicyName -MaxWaitSeconds $MaxWaitForPolicySeconds
                    if (-not $waitResult) {
                        Write-Log "  Policy still not ready, attempting anyway..." -Level WARNING
                    }
                }
                
                $body = @{
                    properties = @{
                        priority = $rcg.properties.priority
                        ruleCollections = $rcg.properties.ruleCollections
                    }
                } | ConvertTo-Json -Depth 20
                
                $putUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$TargetResourceGroup/providers/Microsoft.Network/firewallPolicies/$TargetPolicyName/ruleCollectionGroups/${rcgName}?api-version=$apiVersion"
                
                # Try to create the RCG with enhanced retry logic
                $operationStartTime = Get-Date
                
                try {
                    $response = Invoke-AzureRestWithRetry `
                        -Method PUT `
                        -Uri $putUri `
                        -Headers $headers `
                        -Body $body `
                        -MaxRetries $MaxRetries `
                        -InitialRetryDelay $InitialRetryDelaySeconds `
                        -MaxOperationWaitSeconds $MaxWaitForOperationSeconds
                    
                    # If we get here, the operation was accepted or completed
                    Write-Log "  RCG operation initiated, monitoring status..." -Level INFO
                    
                    # Poll for completion using the policy status
                    $waitSuccess = Wait-PolicyReady -ResourceGroup $TargetResourceGroup -PolicyName $TargetPolicyName -MaxWaitSeconds $MaxWaitForPolicySeconds
                    
                    if ($waitSuccess) {
                        $operationTime = [math]::Round(((Get-Date) - $operationStartTime).TotalSeconds)
                        Write-Log "  RCG copied successfully in ${operationTime}s" -Level SUCCESS
                        $successCount++
                    } else {
                        Write-Log "  RCG operation did not complete in expected time" -Level WARNING
                        $failedRcgs += $rcgName
                    }
                    
                } catch {
                    $copyError = $_.Exception.Message
                    Write-Log "  Failed to copy RCG: $copyError" -Level ERROR
                    $failedRcgs += $rcgName
                }
                
                # Small delay between operations to prevent overwhelming the API
                if ($count -lt $sourceRcgs.Count) {
                    Write-Log "  Waiting ${MinDelayBetweenRCGSeconds}s before next operation..." -Level INFO
                    Start-Sleep -Seconds $MinDelayBetweenRCGSeconds
                }
                
                # Health check after batch
                if ($batchCount -ge $BatchSize -and $count -lt $sourceRcgs.Count) {
                    Write-Log "  Batch of $BatchSize completed, checking overall policy health..." -Level INFO
                    
                    # Ensure policy is stable
                    $policyHealthy = Wait-PolicyReady -ResourceGroup $TargetResourceGroup -PolicyName $TargetPolicyName -MaxWaitSeconds 60
                    
                    if (-not $policyHealthy) {
                        Write-Log "  Policy health check failed, waiting for recovery..." -Level WARNING
                        $recoveryResult = Wait-PolicyReady -ResourceGroup $TargetResourceGroup -PolicyName $TargetPolicyName -MaxWaitSeconds $MaxWaitForPolicySeconds
                        if (-not $recoveryResult) {
                            Write-Log "  Policy recovery failed, continuing anyway..." -Level WARNING
                        }
                    }
                    
                    $batchCount = 0
                    
                    # Refresh the access token after batch
                    try {
                        $newToken = (Get-AzAccessToken -ResourceUrl 'https://management.azure.com/').Token
                        if ($newToken) {
                            $token = $newToken
                            $headers['Authorization'] = "Bearer $token"
                            Write-Log "  Access token refreshed" -Level INFO
                        }
                    } catch {
                        $tokenRefreshError = $_.Exception.Message
                        Write-Log "  Failed to refresh token: $tokenRefreshError" -Level WARNING
                    }
                }
            }
            
            # Report on results
            Write-Log "RCG Copy Results: $successCount succeeded, $($failedRcgs.Count) failed" -Level INFO
            
            if ($failedRcgs.Count -gt 0) {
                Write-Log "WARNING: $($failedRcgs.Count) RCG(s) failed to copy:" -Level WARNING
                foreach ($failed in $failedRcgs) {
                    Write-Log "  - $failed" -Level WARNING
                }
                Write-Log "You may need to retry these manually or investigate further" -Level WARNING
            }
        }
    }

    # === VERIFICATION ===
    if (-not $WhatIfMode) {
        Write-Log "=== VERIFICATION ===" -Level INFO
        
        # Final wait to ensure everything is settled
        if ($isFirewallActive) {
            Write-Log "Waiting for final policy stabilization (60s)..." -Level INFO
            Start-Sleep -Seconds 60
        }
        
        try {
            $finalPolicy = Get-AzFirewallPolicy -ResourceGroupName $TargetResourceGroup -Name $TargetPolicyName -ErrorAction Stop
            
            # Verify DNS
            if ($sourcePolicy.DnsSettings -and $finalPolicy.DnsSettings) {
                $sourceServers = if ($sourcePolicy.DnsSettings.Servers) { $sourcePolicy.DnsSettings.Servers -join ',' } else { "" }
                $targetServers = if ($finalPolicy.DnsSettings.Servers) { $finalPolicy.DnsSettings.Servers -join ',' } else { "" }
                $dnsMatch = $sourceServers -eq $targetServers
                Write-Log "DNS Settings: $(if($dnsMatch){'PASS'}else{'FAIL'})" -Level $(if($dnsMatch){'SUCCESS'}else{'WARNING'})
            }
            
            # Verify Threat Intel
            if ($sourcePolicy.ThreatIntelMode -and $finalPolicy.ThreatIntelMode) {
                $tiMatch = $finalPolicy.ThreatIntelMode -eq $sourcePolicy.ThreatIntelMode
                Write-Log "Threat Intel: $(if($tiMatch){'PASS'}else{'FAIL'})" -Level $(if($tiMatch){'SUCCESS'}else{'WARNING'})
            }
            
            # Verify RCG count with retry
            $finalRcgs = @()
            $verifyRetries = 0
            while ($verifyRetries -lt 3) {
                try { 
                    $finalRcgsResponse = Invoke-RestMethod -Method GET -Uri $tgtListUri -Headers $headers -ErrorAction Stop
                    $finalRcgs = $finalRcgsResponse.value
                    break
                } catch {
                    $verifyRetries++
                    Write-Log "Failed to get final RCG count, retry $verifyRetries/3" -Level WARNING
                    if ($verifyRetries -lt 3) {
                        Start-Sleep -Seconds 10
                    }
                }
            }
            
            $sourceRcgCount = if ($sourceRcgs) { $sourceRcgs.Count } else { 0 }
            $finalRcgCount = if ($finalRcgs) { $finalRcgs.Count } else { 0 }
            $rcgMatch = $finalRcgCount -eq $sourceRcgCount
            
            Write-Log "RCG Count: $(if($rcgMatch){'PASS'}else{'FAIL'}) (Source: $sourceRcgCount, Target: $finalRcgCount)" -Level $(if($rcgMatch){'SUCCESS'}else{'WARNING'})
            
            if (-not $rcgMatch -and $sourceRcgs -and $finalRcgs) {
                Write-Log "RCG mismatch details:" -Level WARNING
                $sourceNames = $sourceRcgs | ForEach-Object { $_.name } | Sort-Object
                $targetNames = $finalRcgs | ForEach-Object { $_.name } | Sort-Object
                $missing = $sourceNames | Where-Object { $_ -notin $targetNames }
                if ($missing) {
                    Write-Log "  Missing RCGs: $($missing -join ', ')" -Level WARNING
                }
                $extra = $targetNames | Where-Object { $_ -notin $sourceNames }
                if ($extra) {
                    Write-Log "  Extra RCGs: $($extra -join ', ')" -Level WARNING
                }
            }
        } catch {
            $verifyError = $_.Exception.Message
            Write-Log "Error during verification: $verifyError" -Level WARNING
        }
    }

    Write-Log "=== OPERATION COMPLETED ===" -Level SUCCESS
    
    $totalTime = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 2)
    Write-Log "Total execution time: ${totalTime} minutes" -Level INFO
    
} catch {
    $mainError = $_.Exception.Message
    
    # Check if this is an expected exit (resource locks) or unexpected error
    if ($global:ExpectedExit -eq $true -or $mainError -like "*Resource locks detected*") {
        # This is an expected exit - show clean summary
        if ($isAzureAutomation) {
            Write-Output "========================================="
            Write-Output "EXECUTION STOPPED: Resource locks prevent safe operation"
            Write-Output "Action Required: Remove locks or enable ForceContinueWithLocks"
            Write-Output "========================================="
            throw  # Re-throw to ensure runbook fails properly
        }
    } else {
        # Unexpected error - show full details
        $errorLine = $_.InvocationInfo.ScriptLineNumber
        $errorCommand = $_.InvocationInfo.Line
        
        Write-Log "OPERATION FAILED: $mainError" -Level ERROR
        Write-Log "Error at line: $errorLine" -Level ERROR
        if ($errorCommand) {
            Write-Log "Failed command: $($errorCommand.Trim())" -Level ERROR
        }
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level ERROR
        
        # Provide specific guidance based on common errors
        if ($mainError -like "*not found*") {
            Write-Log "Resolution: Verify resource names and resource groups are correct" -Level INFO
        } elseif ($mainError -like "*unauthorized*" -or $mainError -like "*forbidden*") {
            Write-Log "Resolution: Check that the Managed Identity has appropriate permissions" -Level INFO
        } elseif ($mainError -like "*Connect-AzAccount*") {
            Write-Log "Resolution: Ensure proper authentication is configured" -Level INFO
        }
        
        if ($isAzureAutomation) { 
            throw 
        } else {
            exit 1
        }
    }
} finally {
    if (-not $isAzureAutomation -and $transcriptPath) {
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Transcript saved to: $transcriptPath" -Level INFO
    }
}