<#
.SYNOPSIS
    Generates Azure Backup status report for Mercer & Hole infrastructure.

.DESCRIPTION
    This script scans backup vaults across multiple subscriptions and generates
    an HTML report with backup status for all protected VMs. Sends email notifications
    via SendGrid when run in Azure Automation.

.NOTES
    Author  : Aaron Bhatti
    Version : 2.0
    Date    : 2025-09-18

    Prerequisites:
    - Az.Accounts, Az.RecoveryServices, Az.Compute, Az.Resources modules
    - Azure Automation Variable 'SendGridApiKey' for email functionality
    - Managed Identity with appropriate backup vault read permissions
#>

# ============= CONFIGURATION =============
# Set default behavior - always include successful backups
$IncludeSuccessfulBackups = $true

# Email configuration for Azure Runbook
$SendEmail = $true  # Set to $false to disable email sending
$EmailTo = "servicedesk@mercerhole.co.uk"
$EmailFrom = "azuremonitoring@mercerhole.co.uk"
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
Write-Log "=== MERCER & HOLE AZURE BACKUP REPORT STARTED ===" -Level SUCCESS

# Mercer & Hole Configuration
$Config = @{
    InfrastructureSubscription = "00000000-0000-0000-0000-000000000001"
    IdentitySubscription = "00000000-0000-0000-0000-000000000002"
    BackupVaults = @(
        @{ SubscriptionId = "00000000-0000-0000-0000-000000000001"; VaultName = "rsv-example-inf-recovery-region"; Description = "Infrastructure Backup" }
        @{ SubscriptionId = "00000000-0000-0000-0000-000000000002"; VaultName = "rsv-example-idt-recovery-region"; Description = "Identity Backup" }
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
    Write-Log "Using existing Azure connection: $($Context.Account.Id)" -Level INFO
}

# Initialize results
$BackupResults = @()
$OverallStatus = "SUCCESS"

# === BACKUP VAULT SCANNING ===
Write-Log "Starting backup vault scanning..." -Level INFO

# Process each backup vault
foreach ($VaultConfig in $Config.BackupVaults) {
    Write-Log "Processing: $($VaultConfig.Description)" -Level INFO
    Write-Log "  Vault: $($VaultConfig.VaultName)" -Level INFO
    Write-Log "  Subscription: $($VaultConfig.SubscriptionId)" -Level INFO
    
    try {
        # Set subscription context
        Set-AzContext -SubscriptionId $VaultConfig.SubscriptionId | Out-Null
        
        # Get the vault
        $Vault = Get-AzRecoveryServicesVault | Where-Object { $_.Name -eq $VaultConfig.VaultName }
        
        if (-not $Vault) {
            Write-Log "  ERROR: Vault not found" -Level ERROR
            continue
        }

        Write-Log "  SUCCESS: Vault found in $($Vault.ResourceGroupName)" -Level SUCCESS
        Set-AzRecoveryServicesVaultContext -Vault $Vault
        
        # Check backup items
        try {
            $BackupItems = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureVM -WorkloadType AzureVM -ErrorAction SilentlyContinue
            
            if ($BackupItems) {
                Write-Log "  INFO: Found $($BackupItems.Count) backup items" -Level INFO
                
                foreach ($Item in $BackupItems) {
                    $VMName = $Item.VirtualMachineId.Split('/')[-1]
                    Write-Log "    Processing: $VMName" -Level INFO
                    
                    # Get backup status using multiple methods for enhanced policies
                    try {
                        # Method 1: Get recent backup jobs
                        $BackupJobs = Get-AzRecoveryServicesBackupJob -BackupManagementType AzureVM -From (Get-Date).AddDays(-14) -ErrorAction SilentlyContinue | 
                                     Where-Object { $_.WorkloadName -eq $VMName } |
                                     Sort-Object StartTime -Descending | Select-Object -First 1
                        
                        # Method 2: Get latest recovery point (works better with enhanced policies)
                        $LastBackupPoint = $null
                        try {
                            $LastBackupPoint = Get-AzRecoveryServicesBackupRecoveryPoint -Item $Item -ErrorAction SilentlyContinue | 
                                              Sort-Object RecoveryPointTime -Descending | Select-Object -First 1
                        } catch {
                            # Recovery point query failed - continue with job data
                        }
                        
                        # Determine backup status
                        $LastBackupStatus = "Unknown"
                        $LastBackupTime = "N/A"
                        
                        if ($BackupJobs) {
                            $LastBackupStatus = $BackupJobs.Status
                            $LastBackupTime = $BackupJobs.StartTime
                        } elseif ($LastBackupPoint) {
                            $LastBackupStatus = "Completed (from recovery point)"
                            $LastBackupTime = $LastBackupPoint.RecoveryPointTime
                        } elseif ($Item.LastBackupTime) {
                            $LastBackupStatus = "Protected (last backup time available)"
                            $LastBackupTime = $Item.LastBackupTime
                        } else {
                            $LastBackupStatus = "No recent backup found"
                        }
                        
                    } catch {
                        $LastBackupStatus = "Error checking backup status"
                        $LastBackupTime = "Error: $($_.Exception.Message)"
                    }
                    
                    # Add to results if needed
                    if ($LastBackupStatus -ne "Completed" -or $IncludeSuccessfulBackups) {
                        $BackupResults += [PSCustomObject]@{
                            SubscriptionName = (Get-AzContext).Subscription.Name
                            VaultType = $VaultConfig.Description
                            VaultName = $Vault.Name
                            ResourceGroup = $Vault.ResourceGroupName
                            VMName = $VMName
                            Status = $LastBackupStatus
                            LastBackupTime = $LastBackupTime
                            ProtectionState = if ($Item.PSObject.Properties.Name -contains 'ProtectionState') { $Item.ProtectionState } else { 'Unknown' }
                            HealthStatus = if ($Item.PSObject.Properties.Name -contains 'HealthStatus') { $Item.HealthStatus } else { 'Unknown' }
                            PolicyName = if ($Item.PSObject.Properties.Name -contains 'PolicyName') { $Item.PolicyName } else { 'Unknown' }
                        }
                        
                        # Determine if this is an issue
                        if ($LastBackupStatus -notlike "*Completed*" -and $LastBackupStatus -notlike "*Protected*") {
                            $OverallStatus = "WARNING"
                            Write-Log "      WARNING: Issue: $LastBackupStatus" -Level WARNING
                        } else {
                            Write-Log "      SUCCESS: OK: $LastBackupStatus" -Level SUCCESS
                        }
                    } else {
                        Write-Log "      SUCCESS: OK: $LastBackupStatus" -Level SUCCESS
                    }
                }
            } else {
                Write-Log "  WARNING: No backup items found in this vault" -Level WARNING
            }
        }
        catch {
            Write-Log "  ERROR: Failed to get backup items: $($_.Exception.Message)" -Level ERROR
        }
    }
    catch {
        Write-Log "  ERROR: Failed to process vault: $($_.Exception.Message)" -Level ERROR
    }
}

# === GENERATING SUMMARY ===
Write-Log "=== BACKUP SUMMARY REPORT ===" -Level SUCCESS

$StatusColor = switch ($OverallStatus) {
    "SUCCESS" { "Green" }
    "WARNING" { "Yellow" } 
    "CRITICAL" { "Red" }
}

Write-Log "Overall Status: $OverallStatus" -Level INFO
Write-Log "Backup Items Found: $($BackupResults.Count)" -Level INFO

Write-Log "DEBUG: About to calculate failed backups..." -Level INFO
try {
    $FailedBackups = ($BackupResults | Where-Object { $_.Status -notlike "*Completed*" -and $_.Status -notlike "*Protected*" -and $_.Status -ne "N/A" }).Count
    Write-Log "DEBUG: Failed backups calculation completed: $FailedBackups" -Level INFO
} catch {
    Write-Log "ERROR: Failed to calculate failed backups: $($_.Exception.Message)" -Level ERROR
    $FailedBackups = 0
}

if ($FailedBackups -gt 0) {
    Write-Log "Failed/Problem Backups: $FailedBackups" -Level WARNING
}

Write-Log "DEBUG: About to process backup details section..." -Level INFO

# Display results table (temporarily disabled for Azure Automation testing)
if ($BackupResults.Count -gt 0) {
    Write-Log "BACKUP STATUS DETAILS: Found $($BackupResults.Count) items (details in HTML report)" -Level INFO
    # Temporarily commenting out detailed logging to test Azure Automation limits
    # foreach ($Result in $BackupResults) {
    #     $StatusLevel = if ($Result.Status -like "*Completed*" -or $Result.Status -like "*Protected*") { "SUCCESS" } else { "WARNING" }
    #     Write-Log "VM: $($Result.VMName) | Vault: $($Result.VaultType) | Status: $($Result.Status) | Health: $($Result.HealthStatus)" -Level $StatusLevel
    # }
}

# === GENERATING HTML REPORT ===
Write-Log "Generating HTML report..." -Level INFO

try {
    Write-Log "Starting HTML content generation..." -Level INFO
    $ReportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Log "Report date set: $ReportDate" -Level INFO

    $HTMLStatusColor = switch ($OverallStatus) {
    "SUCCESS" { "#28a745" }
    "WARNING" { "#ffc107" } 
    "CRITICAL" { "#dc3545" }
}

# Build HTML content using simple string concatenation
$HTMLLines = @()
$HTMLLines += "<!DOCTYPE html>"
$HTMLLines += "<html>"
$HTMLLines += "<head>"
$HTMLLines += "    <title>Mercer &amp; Hole - Azure Backup Status Report</title>"
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
$HTMLLines += "                <img src=`"https://cnnect.com/wp-content/uploads/2024/05/CNNECT-BLACK.png`" alt=`"Mercer &amp; Hole Logo`" style=`"height: 80px; width: auto;`">"
$HTMLLines += "            </div>"
$HTMLLines += "            <div>"
$HTMLLines += "                <h1>Azure Backup Status Report</h1>"
$HTMLLines += "                <p>Generated on: $ReportDate</p>"
$HTMLLines += "                <p>Multi-Subscription Report: Infrastructure &amp; Identity</p>"
$HTMLLines += "            </div>"
$HTMLLines += "        </div>"
$HTMLLines += "    </div>"
$HTMLLines += "    <div class=`"status`">"
$HTMLLines += "        <h2>Overall Status: $OverallStatus</h2>"
$HTMLLines += "    </div>"
$HTMLLines += "    <div class=`"section`">"
$HTMLLines += "        <h2>Azure Backup Status Summary</h2>"
$HTMLLines += "        <p>Total backup items checked: $($BackupResults.Count)</p>"

# Add backup table if we have results
if ($BackupResults.Count -gt 0) {
    $HTMLLines += "        <table>"
    $HTMLLines += "            <tr>"
    $HTMLLines += "                <th>Subscription</th>"
    $HTMLLines += "                <th>Vault Type</th>"
    $HTMLLines += "                <th>Vault</th>"
    $HTMLLines += "                <th>Resource Group</th>"
    $HTMLLines += "                <th>VM Name</th>"
    $HTMLLines += "                <th>Backup Status</th>"
    $HTMLLines += "                <th>Last Backup</th>"
    $HTMLLines += "                <th>Protection State</th>"
    $HTMLLines += "                <th>Health Status</th>"
    $HTMLLines += "            </tr>"
    
    foreach ($item in $BackupResults) {
        $rowClass = if ($item.Status -like "*Completed*" -or $item.Status -like "*Protected*") { 
            "success" 
        } elseif ($item.Status -eq "InProgress" -or $item.Status -like "*Warning*") { 
            "warning" 
        } else { 
            "critical" 
        }
        
        $HTMLLines += "            <tr class=`"$rowClass`">"
        $HTMLLines += "                <td>" + $item.SubscriptionName + "</td>"
        $HTMLLines += "                <td>" + $item.VaultType + "</td>"
        $HTMLLines += "                <td>" + $item.VaultName + "</td>"
        $HTMLLines += "                <td>" + $item.ResourceGroup + "</td>"
        $HTMLLines += "                <td>" + $item.VMName + "</td>"
        $HTMLLines += "                <td>" + $item.Status + "</td>"
        $HTMLLines += "                <td>" + $item.LastBackupTime + "</td>"
        $HTMLLines += "                <td>" + $item.ProtectionState + "</td>"
        $HTMLLines += "                <td>" + $item.HealthStatus + "</td>"
        $HTMLLines += "            </tr>"
    }
    
    $HTMLLines += "        </table>"
} else {
    $HTMLLines += "        <p>No backup items found or no backup issues to report.</p>"
}

$HTMLLines += "    </div>"
$HTMLLines += "    <div class=`"section`">"
$HTMLLines += "        <h3>Configuration Summary</h3>"
$HTMLLines += "        <p><strong>Infrastructure Subscription:</strong> " + $Config.InfrastructureSubscription + "</p>"
$HTMLLines += "        <p><strong>Identity Subscription:</strong> " + $Config.IdentitySubscription + "</p>"
$HTMLLines += "        <p><strong>Vaults Monitored:</strong> " + $Config.BackupVaults.Count + "</p>"
$HTMLLines += "    </div>"
$HTMLLines += "    <div class=`"section`">"
$HTMLLines += "        <h3>Legend</h3>"
$HTMLLines += "        <p><span class=`"success`" style=`"padding: 2px 5px;`">Green</span> - Healthy/Completed</p>"
$HTMLLines += "        <p><span class=`"warning`" style=`"padding: 2px 5px;`">Yellow</span> - Warning/In Progress</p>"
$HTMLLines += "        <p><span class=`"critical`" style=`"padding: 2px 5px;`">Red</span> - Critical/Failed</p>"
$HTMLLines += "    </div>"
$HTMLLines += "</body>"
$HTMLLines += "</html>"

    # Save HTML report
    Write-Log "Preparing to save HTML report..." -Level INFO
    $HTMLFileName = "Mercer-Hole-Backup-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

    # Use temp directory for Azure Automation
    if ($isAzureAutomation) {
        $HTMLFilePath = Join-Path $env:TEMP $HTMLFileName
        Write-Log "Using Azure Automation temp directory: $HTMLFilePath" -Level INFO
    } else {
        $HTMLFilePath = Join-Path (Get-Location) $HTMLFileName
        Write-Log "Using current directory: $HTMLFilePath" -Level INFO
    }

    # Join all lines and save
    Write-Log "Building HTML content from $($HTMLLines.Count) lines..." -Level INFO
    $HTMLContent = $HTMLLines -join "`r`n"
    Write-Log "Saving HTML file..." -Level INFO
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
                # Temporarily override error action for this specific call
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
                $EmailSubject = "Mercer & Hole Azure Backup Report - $OverallStatus - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
                
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
                                    name = "Mercer & Hole Service Desk"
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
}
catch {
    Write-Log "ERROR: Failed to save HTML report: $($_.Exception.Message)" -Level ERROR
    throw
}

Write-Log "=== BACKUP REPORT COMPLETED SUCCESSFULLY ===" -Level SUCCESS
Write-Log "Report Status: $OverallStatus" -Level INFO
Write-Log "HTML Report: $HTMLFilePath" -Level INFO

# Final status for Azure Automation
if ($isAzureAutomation) {
    Write-Output "Backup report execution completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Output "Overall Status: $OverallStatus"
    Write-Output "Backup Items Scanned: $($BackupResults.Count)"
}

# Exit with appropriate code
if ($OverallStatus -eq "WARNING") {
    exit 2
} elseif ($OverallStatus -eq "CRITICAL") {
    exit 1
} else {
    exit 0
}