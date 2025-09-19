<#
.SYNOPSIS
    Generates Azure Site Recovery status report for CNNECT infrastructure.

.DESCRIPTION
    This script scans ASR vaults across multiple subscriptions and generates
    an HTML report with replication status for all protected VMs. Sends email notifications
    via SendGrid when run in Azure Automation.

.NOTES
    Author  : Aaron Bhatti
    Version : 2.0
    Date    : 2025-09-18

    Prerequisites:
    - Az.Accounts, Az.RecoveryServices, Az.Compute, Az.Resources modules
    - Azure Automation Variable 'SendGridApiKey' for email functionality
    - Managed Identity with appropriate ASR vault read permissions
#>

# ============= CONFIGURATION =============
# Set default behavior - always include healthy replications
$IncludeHealthyReplications = $true

# Email configuration for Azure Runbook
$SendEmail = $true  # Set to $false to disable email sending
$EmailTo = "support@cnnect.com"
$EmailFrom = "azuremonitoring@cnnect.com"
# =========================================

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Check if running in Azure Automation
$isAzureAutomation = $null -ne $env:AUTOMATION_ASSET_ACCOUNTID

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

# ============= MAIN EXECUTION =============
Write-Log "=== CNNECT AZURE SITE RECOVERY REPORT STARTED ===" -Level SUCCESS

# CNNECT Configuration
$Config = @{
    InfrastructureSubscription = "00000000-0000-0000-0000-000000000001"
    IdentitySubscription = "00000000-0000-0000-0000-000000000002"
    ASRVaults = @(
        @{ SubscriptionId = "00000000-0000-0000-0000-000000000001"; VaultName = "rsv-example-inf-recovery-region"; Description = "Infrastructure DR" }
        @{ SubscriptionId = "00000000-0000-0000-0000-000000000002"; VaultName = "rsv-example-id-recovery-region"; Description = "Identity DR" }
    )
}

# === MODULE VALIDATION ===
Write-Log "Checking required modules..." -Level INFO
$RequiredModules = @("Az.Accounts", "Az.RecoveryServices", "Az.Compute", "Az.Resources")
$MissingModules = @()

foreach ($Module in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $Module)) {
        $MissingModules += $Module
    }
}

if ($MissingModules.Count -gt 0) {
    Write-Log "Missing required PowerShell modules:" -Level ERROR
    $MissingModules | ForEach-Object { Write-Log "   - $_" -Level ERROR }
    Write-Log "Install missing modules with: Install-Module -Name $($MissingModules -join ', ') -Force -AllowClobber" -Level ERROR
    throw "Required PowerShell modules are missing"
}
Write-Log "All required modules available" -Level SUCCESS

# === AUTHENTICATION ===
Write-Log "Authenticating to Azure..." -Level INFO

if ($isAzureAutomation) {
    try {
        Connect-AzAccount -Identity -WarningAction SilentlyContinue | Out-Null
        Write-Log "Connected using Managed Identity" -Level SUCCESS
    } catch {
        Write-Log "Failed to connect using Managed Identity: $($_.Exception.Message)" -Level ERROR
        throw
    }
} else {
    $Context = Get-AzContext
    if (-not $Context) {
        throw "Not connected to Azure. Please run Connect-AzAccount first."
    }
    Write-Log "Connected as: $($Context.Account.Id)" -Level INFO
}

# Function to get replicated items using REST API with proper fabric/container hierarchy
function Get-ReplicatedItems {
    param([string]$SubscriptionId, [string]$ResourceGroupName, [string]$VaultName)
    
    try {
        $Context = Get-AzContext
        $Token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($Context.Account, $Context.Environment, $Context.Tenant.Id, $null, "Never", $null, $Context.Environment.ActiveDirectoryServiceEndpointResourceId).AccessToken
        
        $Headers = @{
            'Authorization' = "Bearer $Token"
            'Content-Type' = 'application/json'
        }
        
        $Items = @()
        
        # Step 1: Get fabrics
        $FabricsUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.RecoveryServices/vaults/$VaultName/replicationFabrics?api-version=2024-10-01"
        $FabricsResponse = Invoke-RestMethod -Uri $FabricsUri -Headers $Headers -Method Get
        
        if ($FabricsResponse.value) {
            foreach ($Fabric in $FabricsResponse.value) {
                # Step 2: Get protection containers
                $ContainersUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.RecoveryServices/vaults/$VaultName/replicationFabrics/$($Fabric.name)/replicationProtectionContainers?api-version=2024-10-01"
                $ContainersResponse = Invoke-RestMethod -Uri $ContainersUri -Headers $Headers -Method Get -ErrorAction SilentlyContinue
                
                if ($ContainersResponse.value) {
                    foreach ($Container in $ContainersResponse.value) {
                        # Step 3: Get protected items
                        $ItemsUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.RecoveryServices/vaults/$VaultName/replicationFabrics/$($Fabric.name)/replicationProtectionContainers/$($Container.name)/replicationProtectedItems?api-version=2024-10-01"
                        $ItemsResponse = Invoke-RestMethod -Uri $ItemsUri -Headers $Headers -Method Get -ErrorAction SilentlyContinue
                        
                        if ($ItemsResponse.value) {
                            foreach ($Item in $ItemsResponse.value) {
                                # Step 4: Get recovery points using proper hierarchy
                                $RecoveryPointCount = 0
                                $LatestRecoveryPoint = "Unknown"
                                $RPOMinutes = "Unknown"
                                
                                try {
                                    $RecoveryPointsUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.RecoveryServices/vaults/$VaultName/replicationFabrics/$($Fabric.name)/replicationProtectionContainers/$($Container.name)/replicationProtectedItems/$($Item.name)/recoveryPoints?api-version=2024-10-01"
                                    $RPResponse = Invoke-RestMethod -Uri $RecoveryPointsUri -Headers $Headers -Method Get -ErrorAction SilentlyContinue
                                    
                                    if ($RPResponse.value -and $RPResponse.value.Count -gt 0) {
                                        $RecoveryPointCount = $RPResponse.value.Count
                                        $LatestRP = $RPResponse.value | Sort-Object { [DateTime]$_.properties.recoveryPointTime } -Descending | Select-Object -First 1
                                        if ($LatestRP) {
                                            $LatestRecoveryPoint = [DateTime]$LatestRP.properties.recoveryPointTime
                                            $TimeDiff = (Get-Date) - $LatestRecoveryPoint
                                            $RPOMinutes = [math]::Round($TimeDiff.TotalMinutes, 0)
                                        }
                                    }
                                } catch {
                                    # Silently continue if recovery points can't be retrieved
                                }
                                
                                $Items += [PSCustomObject]@{
                                    VMName = if ($Item.properties.friendlyName) { $Item.properties.friendlyName } else { 'Unknown' }
                                    Health = if ($Item.properties.replicationHealth) { $Item.properties.replicationHealth } else { 'Unknown' }
                                    State = if ($Item.properties.protectionState) { $Item.properties.protectionState } else { 'Unknown' }
                                    VaultName = $VaultName
                                    RecoveryPoints = $RecoveryPointCount
                                    LatestRecoveryPoint = $LatestRecoveryPoint
                                    RPOMinutes = $RPOMinutes
                                    Status = if ($Item.properties.replicationHealth -eq "Normal" -and $Item.properties.protectionState -eq "Protected") { "OK" } else { "WARNING" }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return $Items
    } catch {
        Write-Log "Error retrieving replicated items: $($_.Exception.Message)" -Level ERROR
        return @()
    }
}

# === ASR VAULT SCANNING ===
Write-Log "Starting ASR vault scanning..." -Level INFO

$ASRResults = @()

foreach ($VaultConfig in $Config.ASRVaults) {
    Write-Log "Processing: $($VaultConfig.Description)" -Level INFO
    Write-Log "  Subscription: $($VaultConfig.SubscriptionId)" -Level INFO
    Write-Log "  Vault: $($VaultConfig.VaultName)" -Level INFO
    
    try {
        # Set subscription context
        Set-AzContext -SubscriptionId $VaultConfig.SubscriptionId | Out-Null
        
        # Get the vault
        $Vault = Get-AzRecoveryServicesVault | Where-Object { $_.Name -eq $VaultConfig.VaultName }
        
        if (-not $Vault) {
            Write-Log "  ERROR: Vault '$($VaultConfig.VaultName)' not found" -Level ERROR
            continue
        }

        Write-Log "  SUCCESS: Vault found in $($Vault.ResourceGroupName)" -Level SUCCESS
        
        # Get replication status
        $ReplicationItems = Get-ReplicatedItems -SubscriptionId $VaultConfig.SubscriptionId -ResourceGroupName $Vault.ResourceGroupName -VaultName $VaultConfig.VaultName
        
        if ($ReplicationItems.Count -gt 0) {
            $ASRResults += $ReplicationItems
            Write-Log "  Found $($ReplicationItems.Count) replicated VMs" -Level SUCCESS
        } else {
            Write-Log "  No replicated VMs found" -Level WARNING
        }
        
    } catch {
        Write-Log "  ERROR: Failed to process vault: $($_.Exception.Message)" -Level ERROR
    }
}

# === GENERATING HTML REPORT ===
Write-Log "Generating HTML report..." -Level INFO

$ReportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$TotalVMs = $ASRResults.Count
$HealthyVMs = ($ASRResults | Where-Object { $_.Status -eq "OK" }).Count
$WarningVMs = $TotalVMs - $HealthyVMs

# Determine overall status for header
$OverallStatus = if ($WarningVMs -eq 0) { "SUCCESS" } elseif ($HealthyVMs -gt 0) { "WARNING" } else { "CRITICAL" }
$HTMLStatusColor = switch ($OverallStatus) {
    "SUCCESS" { "#28a745" }
    "WARNING" { "#ffc107" } 
    "CRITICAL" { "#dc3545" }
}

# Build HTML content using same style as backup report
$HTMLLines = @()
$HTMLLines += "<!DOCTYPE html>"
$HTMLLines += "<html>"
$HTMLLines += "<head>"
$HTMLLines += "    <title>CNNECT - Azure Site Recovery Status Report</title>"
$HTMLLines += "    <style>"
$HTMLLines += "        body { font-family: Arial, sans-serif; margin: 20px; }"
$HTMLLines += "        .header { background-color: #003341; color: white; padding: 20px; border-radius: 5px; }"
$HTMLLines += "        .status { background-color: $HTMLStatusColor; color: white; padding: 10px; border-radius: 5px; margin: 10px 0; }"
$HTMLLines += "        .section { margin: 20px 0; }"
$HTMLLines += "        table { width: 100%; border-collapse: collapse; margin: 10px 0; }"
$HTMLLines += "        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }"
$HTMLLines += "        th { background-color: #f2f2f2; }"
$HTMLLines += "        .warning { background-color: #fff3cd; }"
$HTMLLines += "        .critical { background-color: #f8d7da; }"
$HTMLLines += "        .success { background-color: #d4edda; }"
$HTMLLines += "    </style>"
$HTMLLines += "</head>"
$HTMLLines += "<body>"
$HTMLLines += "    <div class=`"header`">"
$HTMLLines += "        <div style=`"display: flex; align-items: center; justify-content: flex-start; gap: 40px;`">"
$HTMLLines += "            <div>"
$HTMLLines += "                <img src=`"https://cnnect.com/wp-content/uploads/2024/05/CNNECT-BLACK.png`" alt=`"CNNECT Logo`" style=`"height: 80px; width: auto;`">"
$HTMLLines += "            </div>"
$HTMLLines += "            <div>"
$HTMLLines += "                <h1>Azure Site Recovery Status Report</h1>"
$HTMLLines += "                <p>Generated on: $ReportDate</p>"
$HTMLLines += "                <p>Multi-Subscription Report: Infrastructure &amp; Identity</p>"
$HTMLLines += "            </div>"
$HTMLLines += "        </div>"
$HTMLLines += "    </div>"
$HTMLLines += "    <div class=`"status`">"
$HTMLLines += "        <h2>Overall Status: $OverallStatus</h2>"
$HTMLLines += "    </div>"
$HTMLLines += "    <div class=`"section`">"
$HTMLLines += "        <h2>Azure Site Recovery Status Summary</h2>"
$HTMLLines += "        <p>Total replicated VMs checked: $TotalVMs</p>"

# Add ASR table if we have results
if ($ASRResults.Count -gt 0) {
    $HTMLLines += "        <table>"
    $HTMLLines += "            <tr>"
    $HTMLLines += "                <th>Subscription</th>"
    $HTMLLines += "                <th>Vault</th>"
    $HTMLLines += "                <th>VM Name</th>"
    $HTMLLines += "                <th>Replication Health</th>"
    $HTMLLines += "                <th>Protection State</th>"
    $HTMLLines += "                <th>Recovery Points</th>"
    $HTMLLines += "                <th>Latest Recovery Point</th>"
    $HTMLLines += "                <th>RPO (minutes ago)</th>"
    $HTMLLines += "                <th>Status</th>"
    $HTMLLines += "            </tr>"
    
    foreach ($VM in ($ASRResults | Sort-Object VaultName, VMName)) {
        $rowClass = if ($VM.Status -eq "OK") { "success" } else { "warning" }
        
        # Determine subscription name
        $SubscriptionName = if ($VM.VaultName -eq "rsv-dr-inf-recovery-ukw") { "Infrastructure" } else { "Identity" }
        
        # Format latest recovery point
        $FormattedRP = if ($VM.LatestRecoveryPoint -eq "Unknown") { "Unknown" } else { $VM.LatestRecoveryPoint.ToString("yyyy-MM-dd HH:mm") }
        
        $HTMLLines += "            <tr class=`"$rowClass`">"
        $HTMLLines += "                <td>$SubscriptionName</td>"
        $HTMLLines += "                <td>$($VM.VaultName)</td>"
        $HTMLLines += "                <td>$($VM.VMName)</td>"
        $HTMLLines += "                <td>$($VM.Health)</td>"
        $HTMLLines += "                <td>$($VM.State)</td>"
        $HTMLLines += "                <td>$($VM.RecoveryPoints)</td>"
        $HTMLLines += "                <td>$FormattedRP</td>"
        $HTMLLines += "                <td>$($VM.RPOMinutes)</td>"
        $HTMLLines += "                <td>$($VM.Status)</td>"
        $HTMLLines += "            </tr>"
    }
    
    $HTMLLines += "        </table>"
} else {
    $HTMLLines += "        <p>No replicated VMs found or no replication issues to report.</p>"
}

$HTMLLines += "    </div>"
$HTMLLines += "</body>"
$HTMLLines += "</html>"

# Save HTML report
try {
    $HTMLFileName = "Mercer-Hole-ASR-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

    # Use temp directory for Azure Automation
    if ($isAzureAutomation) {
        $HTMLFilePath = Join-Path $env:TEMP $HTMLFileName
    } else {
        $HTMLFilePath = Join-Path (Get-Location) $HTMLFileName
    }

    # Join all lines and save
    $HTMLContent = $HTMLLines -join "`r`n"
    $HTMLContent | Out-File -FilePath $HTMLFilePath -Encoding UTF8

    Write-Log "SUCCESS: HTML report saved: $HTMLFilePath" -Level SUCCESS
    
    # Send email in Azure Runbook environment
    if ($SendEmail) {
        Write-Log "Attempting to send email report..." -Level INFO
        try {
            Write-Log "Azure Runbook environment - sending email..." -Level INFO

            # Get SendGrid API key from Azure Automation Variable
            Write-Log "Attempting to retrieve SendGrid API key from Azure Automation Variable..." -Level INFO
            $ApiKey = $null
            try {
                $ApiKey = Get-AutomationVariable -Name "SendGridApiKey" -ErrorAction Stop
                Write-Log "Successfully retrieved SendGrid API key from Azure Automation Variable" -Level SUCCESS
            } catch {
                Write-Log "ERROR: Could not retrieve SendGrid API key from Azure Automation Variable 'SendGridApiKey'" -Level ERROR
                Write-Log "Error details: $($_.Exception.Message)" -Level ERROR
                Write-Log "Please ensure the 'SendGridApiKey' variable is configured in your Automation Account" -Level WARNING

                # Don't throw - just skip email sending
                Write-Log "Email sending will be skipped due to missing API key" -Level WARNING
                $ApiKey = $null
            }
            
            if ($ApiKey) {
                # Send email using SendGrid API
                $EmailSubject = "CNNECT Azure Site Recovery Report - $OverallStatus - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
                
                # Create email body with embedded HTML report
                $EmailBody = $HTMLContent
                
                # Prepare SendGrid API request
                $SendGridUri = "https://api.sendgrid.com/v3/mail/send"
                $Headers = @{
                    "Authorization" = "Bearer $ApiKey"
                    "Content-Type" = "application/json"
                }
                
                $Body = @{
                    personalizations = @(
                        @{
                            to = @(
                                @{
                                    email = $EmailTo
                                    name = "CNNECT Service Desk"
                                }
                            )
                            subject = $EmailSubject
                        }
                    )
                    from = @{
                        email = $EmailFrom
                        name = "Azure Monitoring System"
                    }
                    content = @(
                        @{
                            type = "text/html"
                            value = $EmailBody
                        }
                    )
                } | ConvertTo-Json -Depth 4
                
                # Send email
                $Response = Invoke-RestMethod -Uri $SendGridUri -Method Post -Headers $Headers -Body $Body
                Write-Log "SUCCESS: Email sent via SendGrid" -Level SUCCESS
                Write-Log "Subject: $EmailSubject" -Level INFO
                Write-Log "To: $EmailTo" -Level INFO
            } else {
                Write-Log "WARNING: SendGrid API key not available - email not sent" -Level WARNING
            }
        } catch {
            Write-Log "WARNING: Email sending failed: $($_.Exception.Message)" -Level WARNING
        }
    }
    
    # Running in Azure Runbook - no browser opening needed
    Write-Log "INFO: Report generated for Azure Runbook execution" -Level INFO
    
} catch {
    Write-Log "ERROR: Failed to save HTML report: $($_.Exception.Message)" -Level ERROR
    throw
}

Write-Log "=== ASR REPORT COMPLETED SUCCESSFULLY ===" -Level SUCCESS
Write-Log "Report saved to: $HTMLFilePath" -Level INFO
Write-Log "Total replicated VMs found: $TotalVMs" -Level INFO

if ($TotalVMs -gt 0) {
    Write-Log "Status breakdown:" -Level INFO
    Write-Log "  Healthy: $HealthyVMs" -Level SUCCESS
    Write-Log "  Warning: $WarningVMs" -Level WARNING

    Write-Log "VM Details:" -Level INFO
    foreach ($VM in ($ASRResults | Sort-Object VaultName, VMName)) {
        $Level = if ($VM.Status -eq "OK") { "SUCCESS" } else { "WARNING" }
        $RPOText = if ($VM.RPOMinutes -eq "Unknown") { "Unknown" } else { "$($VM.RPOMinutes) min ago" }
        Write-Log "  $($VM.VMName): $($VM.Health)/$($VM.State) | RPO: $RPOText | Points: $($VM.RecoveryPoints) [$($VM.VaultName)]" -Level $Level
    }
} else {
    Write-Log "No replicated VMs found in configured vaults" -Level WARNING
}

# Final status for Azure Automation
if ($isAzureAutomation) {
    Write-Output "ASR report execution completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Output "Overall Status: $OverallStatus"
    Write-Output "Replicated VMs Scanned: $TotalVMs"
    Write-Output "Healthy VMs: $HealthyVMs"
    Write-Output "Warning VMs: $WarningVMs"
} else {
    Write-Log "Open the HTML file in a web browser to view the formatted report." -Level INFO
}