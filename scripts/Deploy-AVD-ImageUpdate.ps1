#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.DesktopVirtualization, Az.Compute, Az.Network, Az.Resources
<#
.SYNOPSIS
    Automates the deployment of a new Azure Virtual Desktop (AVD) image.

.DESCRIPTION
    This script automates the complete process of updating AVD session hosts with a new image:
    1. Sends notification messages to all active users to save work and sign off
    2. Enables drain mode on all session hosts
    3. Logs out all active user sessions
    4. Removes session hosts from the host pool
    5. Deletes VMs, NICs, and disks from the resource group
    6. Deploys new session hosts with the updated image and joins them to the domain

    IMPORTANT: This script performs destructive operations. Review configuration carefully.

.PARAMETER ApplyChanges
    Set to $true to execute actual changes, or $false for dry run mode (no changes).
    This parameter is mandatory and must be explicitly set when running the script.
    Defaults to $false for safety.

.NOTES
    Author  : Aaron Bhatti
    Version : 1.0.0
    Date    : 2025-10-06

    Prerequisites:
    - Az.Accounts, Az.DesktopVirtualization, Az.Compute, Az.Network, Az.Resources modules
    - Managed Identity with appropriate AVD, VM, and Network permissions
    - New VM image already created and available
    - Domain join credentials stored in Azure Automation credentials
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [bool]$ApplyChanges = $false
)

# ============= CONFIGURATION =============
$TenantId = "3ec094fc-4da6-40af-8073-0303aaa9c094"
$SubscriptionId = "7d39481f-dce1-4671-a71b-619dde0d9fa1"  # Update with your AVD subscription ID

# AVD Configuration
$HostPoolResourceGroup = "rg-prod-avd-uks-service"
$HostPoolName = "vdmspool-prod-test-uks"
$SessionHostResourceGroup = "rg-prod-avd-uks-host-pool-test"

# New Image Configuration
$NewImageResourceId = "/subscriptions/7d39481f-dce1-4671-a71b-619dde0d9fa1/resourceGroups/rg-prod-avd-uks-aib-service/providers/Microsoft.Compute/galleries/avdgallery_prod_uks/images/avdimage-win11-24h2-avd-m365/versions/latest"
$VMSize = "Standard_E8as_v6"
$VMNamePrefix = "mh-avd-test"  # Max 13 chars to allow for -0, -1 suffix (15 char Windows limit)
$NumberOfInstances = 3

# Domain Join Configuration (Credentials stored in Azure Automation)
$DomainName = "mercerhole.co.uk"
$DomainJoinCredentialName = "AVDDomainJoinAccount"  # Name of credential asset in Azure Automation
$OUPath = "OU=Test,OU=Prod,OU=AVD,OU=MercerHole,DC=mercerhole,DC=co,DC=uk"

# Network Configuration
$VNetResourceGroup = "rg-prod-avd-uks-network"
$VNetName = "vnet-prod-avd-uks"
$SubnetName = "snet-prod-test-desktop-uks"

# Operation Settings
$UserNotificationTimeMinutes = 1       # Time to give users before logging them off
$UserNotificationMessage = "System maintenance will begin in 1 minutes. Please save your work and sign off."
$MaxWaitForLogoffMinutes = 30          # Maximum time to wait for users to log off
$DeleteOldDisks = $true                # Delete disks from deleted VMs
$WaitTimeoutMinutes = 60               # Timeout for ARM deployment operations
# =========================================

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Check if running in Azure Automation
$isAzureAutomation = $null -ne $env:AUTOMATION_ASSET_ACCOUNTID

# Set WhatIfMode based on ApplyChanges parameter
$WhatIfMode = -not $ApplyChanges

# Display execution mode
if ($isAzureAutomation) {
    if ($WhatIfMode) {
        Write-Output "=== DRY RUN MODE - No changes will be made ==="
    } else {
        Write-Output "=== ACTUAL MODE - Changes will be made to your environment ==="
    }
} else {
    if ($WhatIfMode) {
        Write-Host "`n=== DRY RUN MODE - No changes will be made ===`n" -ForegroundColor Green
    } else {
        Write-Host "`n=== ACTUAL MODE - Changes will be made to your environment ===`n" -ForegroundColor Red
    }
}

# Initialize transcript (local only)
if (-not $isAzureAutomation) {
    $transcriptPath = Join-Path $env:TEMP "DeployAVDImageUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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

# Send message to all active user sessions
function Send-UserNotifications {
    param(
        [Parameter(Mandatory)][string]$HostPoolRG,
        [Parameter(Mandatory)][string]$HostPoolName,
        [Parameter(Mandatory)][string]$Message
    )

    Write-Log "Sending notifications to active user sessions..." -Level INFO

    try {
        # Get all session hosts
        $sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $HostPoolRG -HostPoolName $HostPoolName
        $notificationsSent = 0

        foreach ($sessionHost in $sessionHosts) {
            # Get active user sessions on this host
            $sessionHostName = ($sessionHost.Name -split '/')[-1]
            $userSessions = Get-AzWvdUserSession -ResourceGroupName $HostPoolRG -HostPoolName $HostPoolName -SessionHostName $sessionHostName -ErrorAction SilentlyContinue

            foreach ($session in $userSessions) {
                if ($session.SessionState -eq 'Active') {
                    try {
                        $sessionName = ($session.Name -split '/')[-1]
                        if (-not $WhatIfMode) {
                            Send-AzWvdUserSessionMessage -ResourceGroupName $HostPoolRG `
                                -HostPoolName $HostPoolName `
                                -SessionHostName $sessionHostName `
                                -UserSessionId $sessionName `
                                -MessageTitle "System Maintenance" `
                                -MessageBody $Message

                            Write-Log "  Sent notification to user: $($session.UserPrincipalName) on $sessionHostName" -Level SUCCESS
                            $notificationsSent++
                        } else {
                            Write-Log "  WHATIF: Would send notification to user: $($session.UserPrincipalName) on $sessionHostName" -Level WARNING
                        }
                    } catch {
                        Write-Log "  WARNING: Failed to send message to session: $($_.Exception.Message)" -Level WARNING
                    }
                }
            }
        }

        Write-Log "Notifications sent to $notificationsSent active user(s)" -Level SUCCESS
        return $notificationsSent
    } catch {
        Write-Log "ERROR: Failed to send user notifications: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

# Enable drain mode on all session hosts
function Enable-DrainMode {
    param(
        [Parameter(Mandatory)][string]$HostPoolRG,
        [Parameter(Mandatory)][string]$HostPoolName
    )

    Write-Log "Enabling drain mode on all session hosts..." -Level INFO

    try {
        $sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $HostPoolRG -HostPoolName $HostPoolName
        $drainedCount = 0

        foreach ($sessionHost in $sessionHosts) {
            $sessionHostName = ($sessionHost.Name -split '/')[-1]

            if (-not $WhatIfMode) {
                Update-AzWvdSessionHost -ResourceGroupName $HostPoolRG `
                    -HostPoolName $HostPoolName `
                    -Name $sessionHostName `
                    -AllowNewSession:$false | Out-Null

                Write-Log "  Enabled drain mode on: $sessionHostName" -Level SUCCESS
                $drainedCount++
            } else {
                Write-Log "  WHATIF: Would enable drain mode on: $sessionHostName" -Level WARNING
            }
        }

        Write-Log "Drain mode enabled on $drainedCount session host(s)" -Level SUCCESS
        return $sessionHosts
    } catch {
        Write-Log "ERROR: Failed to enable drain mode: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

# Log off all user sessions
function Disconnect-AllUserSessions {
    param(
        [Parameter(Mandatory)][string]$HostPoolRG,
        [Parameter(Mandatory)][string]$HostPoolName,
        [int]$MaxWaitMinutes = 30
    )

    Write-Log "Logging off all user sessions..." -Level INFO

    try {
        $sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $HostPoolRG -HostPoolName $HostPoolName
        $loggedOffCount = 0

        foreach ($sessionHost in $sessionHosts) {
            $sessionHostName = ($sessionHost.Name -split '/')[-1]
            $userSessions = Get-AzWvdUserSession -ResourceGroupName $HostPoolRG -HostPoolName $HostPoolName -SessionHostName $sessionHostName -ErrorAction SilentlyContinue

            foreach ($session in $userSessions) {
                try {
                    $sessionName = ($session.Name -split '/')[-1]
                    if (-not $WhatIfMode) {
                        Remove-AzWvdUserSession -ResourceGroupName $HostPoolRG `
                            -HostPoolName $HostPoolName `
                            -SessionHostName $sessionHostName `
                            -Id $sessionName -ErrorAction SilentlyContinue

                        Write-Log "  Logged off user: $($session.UserPrincipalName) from $sessionHostName" -Level SUCCESS
                        $loggedOffCount++
                    } else {
                        Write-Log "  WHATIF: Would log off user: $($session.UserPrincipalName) from $sessionHostName" -Level WARNING
                    }
                } catch {
                    Write-Log "  WARNING: Failed to log off session: $($_.Exception.Message)" -Level WARNING
                }
            }
        }

        Write-Log "Logged off $loggedOffCount user session(s)" -Level SUCCESS

        # Wait and verify all sessions are disconnected
        if (-not $WhatIfMode) {
            Write-Log "Waiting for sessions to fully disconnect..." -Level INFO
            Start-Sleep -Seconds 30

            # Verify no active sessions remain
            $remainingSessions = 0
            foreach ($sessionHost in $sessionHosts) {
                $sessionHostName = ($sessionHost.Name -split '/')[-1]
                $sessions = Get-AzWvdUserSession -ResourceGroupName $HostPoolRG -HostPoolName $HostPoolName -SessionHostName $sessionHostName -ErrorAction SilentlyContinue
                $remainingSessions += $sessions.Count
            }

            if ($remainingSessions -gt 0) {
                Write-Log "WARNING: $remainingSessions session(s) still active after logoff attempt" -Level WARNING
            } else {
                Write-Log "All user sessions successfully disconnected" -Level SUCCESS
            }
        }
    } catch {
        Write-Log "ERROR: Failed to log off user sessions: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

# Remove session hosts from host pool and return VM information
function Remove-SessionHostsFromPool {
    param(
        [Parameter(Mandatory)][string]$HostPoolRG,
        [Parameter(Mandatory)][string]$HostPoolName
    )

    Write-Log "Removing session hosts from host pool..." -Level INFO

    try {
        $sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $HostPoolRG -HostPoolName $HostPoolName
        $vmNames = @()
        $removedCount = 0

        foreach ($sessionHost in $sessionHosts) {
            $sessionHostName = ($sessionHost.Name -split '/')[-1]
            # Extract VM name (format: hostname.domain)
            $vmName = $sessionHostName -replace '\..*$', ''
            $vmNames += $vmName

            if (-not $WhatIfMode) {
                Remove-AzWvdSessionHost -ResourceGroupName $HostPoolRG `
                    -HostPoolName $HostPoolName `
                    -Name $sessionHostName -Force

                Write-Log "  Removed session host: $sessionHostName (VM: $vmName)" -Level SUCCESS
                $removedCount++
            } else {
                Write-Log "  WHATIF: Would remove session host: $sessionHostName (VM: $vmName)" -Level WARNING
            }
        }

        Write-Log "Removed $removedCount session host(s) from pool" -Level SUCCESS
        Write-Log "VM names identified: $($vmNames -join ', ')" -Level INFO

        return $vmNames
    } catch {
        Write-Log "ERROR: Failed to remove session hosts: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

# Delete VMs, NICs, and disks
function Remove-SessionHostVMs {
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][array]$VMNames,
        [bool]$DeleteDisks = $true
    )

    Write-Log "Deleting session host VMs and associated resources..." -Level INFO

    try {
        foreach ($vmName in $VMNames) {
            Write-Log "Processing VM: $vmName" -Level INFO

            # Get VM details before deletion
            $vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $vmName -ErrorAction SilentlyContinue

            if ($vm) {
                # Store NIC and disk information
                $nicIds = $vm.NetworkProfile.NetworkInterfaces.Id
                $osDiskName = $vm.StorageProfile.OsDisk.Name
                $dataDisks = $vm.StorageProfile.DataDisks | ForEach-Object { $_.Name }

                # Delete VM
                if (-not $WhatIfMode) {
                    Write-Log "  Deleting VM: $vmName..." -Level INFO
                    Remove-AzVM -ResourceGroupName $ResourceGroup -Name $vmName -Force | Out-Null
                    Write-Log "  VM deleted successfully" -Level SUCCESS
                } else {
                    Write-Log "  WHATIF: Would delete VM: $vmName" -Level WARNING
                }

                # Delete NICs
                foreach ($nicId in $nicIds) {
                    $nicName = ($nicId -split '/')[-1]
                    if (-not $WhatIfMode) {
                        Write-Log "  Deleting NIC: $nicName..." -Level INFO
                        Remove-AzNetworkInterface -ResourceGroupName $ResourceGroup -Name $nicName -Force | Out-Null
                        Write-Log "  NIC deleted successfully" -Level SUCCESS
                    } else {
                        Write-Log "  WHATIF: Would delete NIC: $nicName" -Level WARNING
                    }
                }

                # Delete disks if requested
                if ($DeleteDisks) {
                    # Delete OS disk
                    if ($osDiskName -and -not $WhatIfMode) {
                        Write-Log "  Deleting OS disk: $osDiskName..." -Level INFO
                        Remove-AzDisk -ResourceGroupName $ResourceGroup -DiskName $osDiskName -Force | Out-Null
                        Write-Log "  OS disk deleted successfully" -Level SUCCESS
                    } elseif ($osDiskName) {
                        Write-Log "  WHATIF: Would delete OS disk: $osDiskName" -Level WARNING
                    }

                    # Delete data disks
                    foreach ($dataDisk in $dataDisks) {
                        if ($dataDisk -and -not $WhatIfMode) {
                            Write-Log "  Deleting data disk: $dataDisk..." -Level INFO
                            Remove-AzDisk -ResourceGroupName $ResourceGroup -DiskName $dataDisk -Force | Out-Null
                            Write-Log "  Data disk deleted successfully" -Level SUCCESS
                        } elseif ($dataDisk) {
                            Write-Log "  WHATIF: Would delete data disk: $dataDisk" -Level WARNING
                        }
                    }
                }
            } else {
                Write-Log "  WARNING: VM not found: $vmName" -Level WARNING
            }
        }

        Write-Log "VM deletion completed" -Level SUCCESS
    } catch {
        Write-Log "ERROR: Failed to delete VMs: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

# Deploy new session hosts using ARM template
function Deploy-NewSessionHosts {
    param(
        [Parameter(Mandatory)][string]$HostPoolRG,
        [Parameter(Mandatory)][string]$HostPoolName,
        [Parameter(Mandatory)][string]$SessionHostRG,
        [Parameter(Mandatory)][string]$ImageId,
        [Parameter(Mandatory)][string]$VMNamePrefix,
        [Parameter(Mandatory)][int]$Count,
        [Parameter(Mandatory)][string]$VMSize,
        [Parameter(Mandatory)][string]$VNetRG,
        [Parameter(Mandatory)][string]$VNetName,
        [Parameter(Mandatory)][string]$SubnetName,
        [Parameter(Mandatory)][PSCredential]$DomainJoinCredential,
        [Parameter(Mandatory)][string]$DomainFQDN,
        [string]$OUPath
    )

    Write-Log "Deploying $Count new session hosts using ARM template..." -Level INFO

    if ($WhatIfMode) {
        Write-Log "WHATIF: Would deploy $Count VMs with prefix '$VMNamePrefix' using image: $ImageId" -Level WARNING
        return @()
    }

    try {
        # Get subnet ID
        $vnet = Get-AzVirtualNetwork -ResourceGroupName $VNetRG -Name $VNetName
        $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $SubnetName }

        if (-not $subnet) {
            throw "Subnet '$SubnetName' not found in VNet '$VNetName'"
        }

        $subnetId = $subnet.Id
        $location = $vnet.Location

        # Get host pool registration token
        Write-Log "Generating host pool registration token..." -Level INFO
        $registrationInfo = New-AzWvdRegistrationInfo -ResourceGroupName $HostPoolRG `
            -HostPoolName $HostPoolName `
            -ExpirationTime (Get-Date).AddHours(4) `
            -ErrorAction Stop

        $registrationToken = $registrationInfo.Token
        Write-Log "Registration token generated successfully" -Level SUCCESS

        # Resolve actual image version if using 'latest'
        $actualImageVersion = "unknown"
        try {
            if ($ImageId -match '/galleries/([^/]+)/images/([^/]+)/versions/(.+)$') {
                $galleryName = $matches[1]
                $imageName = $matches[2]
                $versionRef = $matches[3]
                $imageRG = ($ImageId -split '/resourceGroups/')[1].Split('/')[0]

                if ($versionRef -eq "latest") {
                    Write-Log "Resolving 'latest' image version..." -Level INFO
                    $imageVersions = Get-AzGalleryImageVersion -ResourceGroupName $imageRG `
                        -GalleryName $galleryName `
                        -GalleryImageName $imageName `
                        -ErrorAction Stop

                    $latestVersion = $imageVersions | Sort-Object -Property Name -Descending | Select-Object -First 1
                    $actualImageVersion = $latestVersion.Name
                    Write-Log "Resolved latest version: $actualImageVersion" -Level SUCCESS
                } else {
                    $actualImageVersion = $versionRef
                    Write-Log "Using specified image version: $actualImageVersion" -Level INFO
                }
            }
        } catch {
            Write-Log "WARNING: Could not resolve image version, will use 'unknown': $($_.Exception.Message)" -Level WARNING
            $actualImageVersion = "unknown"
        }

        # Embedded ARM template for AVD session host deployment with copy loop
        $armTemplate = @'
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "vmNamePrefix": { "type": "string" },
    "vmCount": { "type": "int" },
    "vmSize": { "type": "string" },
    "imageId": { "type": "string" },
    "subnetId": { "type": "string" },
    "location": { "type": "string", "defaultValue": "[resourceGroup().location]" },
    "domainToJoin": { "type": "string" },
    "domainUsername": { "type": "string" },
    "domainPassword": { "type": "securestring" },
    "ouPath": { "type": "string", "defaultValue": "" },
    "hostPoolName": { "type": "string" },
    "hostPoolToken": { "type": "securestring" },
    "vmAdminUsername": { "type": "string", "defaultValue": "azureadmin" },
    "vmAdminPassword": { "type": "securestring" },
    "licenseType": {
      "type": "string",
      "defaultValue": "Windows_Client",
      "allowedValues": ["Windows_Client", "Windows_Server", "None"]
    }
  },
  "variables": {
    "dscExtensionName": "Microsoft.PowerShell.DSC",
    "dscConfiguration": {
      "configuration": {
        "url": "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_01-20-2022.zip",
        "script": "Configuration.ps1",
        "function": "AddSessionHost"
      },
      "configurationArguments": {
        "hostPoolName": "[parameters('hostPoolName')]",
        "registrationInfoToken": "[parameters('hostPoolToken')]"
      }
    }
  },
  "resources": [
    {
      "type": "Microsoft.Network/networkInterfaces",
      "apiVersion": "2023-04-01",
      "name": "[concat(parameters('vmNamePrefix'), '-', copyIndex(), '-nic')]",
      "location": "[parameters('location')]",
      "copy": {
        "name": "nicCopy",
        "count": "[parameters('vmCount')]"
      },
      "properties": {
        "ipConfigurations": [
          {
            "name": "ipconfig1",
            "properties": {
              "subnet": { "id": "[parameters('subnetId')]" },
              "privateIPAllocationMethod": "Dynamic"
            }
          }
        ]
      }
    },
    {
      "type": "Microsoft.Compute/virtualMachines",
      "apiVersion": "2023-03-01",
      "name": "[concat(parameters('vmNamePrefix'), '-', copyIndex())]",
      "location": "[parameters('location')]",
      "copy": {
        "name": "vmCopy",
        "count": "[parameters('vmCount')]"
      },
      "dependsOn": [
        "[resourceId('Microsoft.Network/networkInterfaces', concat(parameters('vmNamePrefix'), '-', copyIndex(), '-nic'))]"
      ],
      "properties": {
        "hardwareProfile": { "vmSize": "[parameters('vmSize')]" },
        "storageProfile": {
          "imageReference": { "id": "[parameters('imageId')]" },
          "osDisk": {
            "name": "[concat(parameters('vmNamePrefix'), '-', copyIndex(), '-osdisk')]",
            "createOption": "FromImage",
            "caching": "ReadWrite",
            "managedDisk": { "storageAccountType": "Premium_LRS" }
          }
        },
        "osProfile": {
          "computerName": "[concat(parameters('vmNamePrefix'), '-', copyIndex())]",
          "adminUsername": "[parameters('vmAdminUsername')]",
          "adminPassword": "[parameters('vmAdminPassword')]",
          "windowsConfiguration": {
            "provisionVMAgent": true,
            "enableAutomaticUpdates": true
          }
        },
        "networkProfile": {
          "networkInterfaces": [
            { "id": "[resourceId('Microsoft.Network/networkInterfaces', concat(parameters('vmNamePrefix'), '-', copyIndex(), '-nic'))]" }
          ]
        },
        "licenseType": "[parameters('licenseType')]"
      }
    },
    {
      "type": "Microsoft.Compute/virtualMachines/extensions",
      "apiVersion": "2023-03-01",
      "name": "[concat(parameters('vmNamePrefix'), '-', copyIndex(), '/joindomain')]",
      "location": "[parameters('location')]",
      "copy": {
        "name": "domainJoinCopy",
        "count": "[parameters('vmCount')]"
      },
      "dependsOn": [
        "[resourceId('Microsoft.Compute/virtualMachines', concat(parameters('vmNamePrefix'), '-', copyIndex()))]"
      ],
      "properties": {
        "publisher": "Microsoft.Compute",
        "type": "JsonADDomainExtension",
        "typeHandlerVersion": "1.3",
        "autoUpgradeMinorVersion": true,
        "settings": {
          "name": "[parameters('domainToJoin')]",
          "ouPath": "[parameters('ouPath')]",
          "user": "[concat(parameters('domainToJoin'), '\\', parameters('domainUsername'))]",
          "restart": "true",
          "options": "3"
        },
        "protectedSettings": {
          "password": "[parameters('domainPassword')]"
        }
      }
    },
    {
      "type": "Microsoft.Compute/virtualMachines/extensions",
      "apiVersion": "2023-03-01",
      "name": "[concat(parameters('vmNamePrefix'), '-', copyIndex(), '/', variables('dscExtensionName'))]",
      "location": "[parameters('location')]",
      "copy": {
        "name": "dscCopy",
        "count": "[parameters('vmCount')]"
      },
      "dependsOn": [
        "[resourceId('Microsoft.Compute/virtualMachines', concat(parameters('vmNamePrefix'), '-', copyIndex()))]",
        "[resourceId('Microsoft.Compute/virtualMachines/extensions', concat(parameters('vmNamePrefix'), '-', copyIndex()), 'joindomain')]"
      ],
      "properties": {
        "publisher": "Microsoft.Powershell",
        "type": "DSC",
        "typeHandlerVersion": "2.73",
        "autoUpgradeMinorVersion": true,
        "settings": {
          "modulesUrl": "[variables('dscConfiguration').configuration.url]",
          "configurationFunction": "[concat(variables('dscConfiguration').configuration.script, '\\', variables('dscConfiguration').configuration.function)]",
          "properties": {
            "hostPoolName": "[variables('dscConfiguration').configurationArguments.hostPoolName]",
            "registrationInfoToken": "[variables('dscConfiguration').configurationArguments.registrationInfoToken]"
          }
        }
      }
    }
  ],
  "outputs": {
    "vmNames": {
      "type": "array",
      "copy": {
        "count": "[parameters('vmCount')]",
        "input": "[concat(parameters('vmNamePrefix'), '-', copyIndex())]"
      }
    }
  }
}
'@

        Write-Log "Using embedded ARM template for parallel deployment" -Level INFO
        Write-Log "Deploying $Count VMs in parallel..." -Level INFO

        # Generate random 12-character password for local admin (plain text for ARM template)
        $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%'
        $localAdminPasswordPlain = -join ((1..12) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })

        # Convert domain password to plain text for ARM template
        $domainPasswordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($DomainJoinCredential.Password)
        )

        # Prepare template parameters for all VMs
        $templateParameters = @{
            vmNamePrefix = $VMNamePrefix
            vmCount = $Count
            vmSize = $VMSize
            imageId = $ImageId
            subnetId = $subnetId
            location = $location
            domainToJoin = $DomainFQDN
            domainUsername = $DomainJoinCredential.UserName
            domainPassword = $domainPasswordPlain
            ouPath = $OUPath
            hostPoolName = $HostPoolName
            hostPoolToken = $registrationToken
            vmAdminPassword = $localAdminPasswordPlain
            licenseType = "Windows_Client"
        }

        # Deploy ARM template once for all VMs
        $deploymentName = "avd-deploy-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Log "Starting ARM deployment: $deploymentName" -Level INFO

        try {
            # Save template to temp file for deployment
            $tempTemplateFile = [System.IO.Path]::GetTempFileName()
            $armTemplate | Out-File -FilePath $tempTemplateFile -Encoding utf8 -Force

            $deployment = New-AzResourceGroupDeployment -ResourceGroupName $SessionHostRG `
                -Name $deploymentName `
                -TemplateFile $tempTemplateFile `
                -TemplateParameterObject $templateParameters `
                -ErrorAction Stop

            # Clean up temp file
            Remove-Item -Path $tempTemplateFile -Force -ErrorAction SilentlyContinue

            if ($deployment.ProvisioningState -eq 'Succeeded') {
                Write-Log "All VMs deployed successfully" -Level SUCCESS

                # Get deployed VM names from output
                $deployedVMs = $deployment.Outputs.vmNames.Value
                Write-Log "Deployed VMs: $($deployedVMs -join ', ')" -Level SUCCESS

                # Tag all VMs with image version
                foreach ($vmName in $deployedVMs) {
                    try {
                        $tags = @{
                            "ImageVersion" = $actualImageVersion
                            "DeploymentDate" = (Get-Date -Format "yyyy-MM-dd")
                            "DeployedBy" = "AVD-ImageUpdate-Automation"
                        }

                        Update-AzTag -ResourceId "/subscriptions/$SubscriptionId/resourceGroups/$SessionHostRG/providers/Microsoft.Compute/virtualMachines/$vmName" `
                            -Tag $tags -Operation Merge -ErrorAction Stop

                        Write-Log "  VM $vmName tagged with image version: $actualImageVersion" -Level SUCCESS
                    } catch {
                        Write-Log "  WARNING: Failed to tag VM $vmName : $($_.Exception.Message)" -Level WARNING
                    }
                }
            } else {
                Write-Log "ERROR: Deployment failed with state: $($deployment.ProvisioningState)" -Level ERROR
                throw "Deployment failed with state: $($deployment.ProvisioningState)"
            }
        } catch {
            Write-Log "ERROR: Failed to deploy VMs: $($_.Exception.Message)" -Level ERROR
            throw "VM deployment failed, stopping script execution"
        }

        Write-Log "Successfully deployed $($deployedVMs.Count) of $Count session host(s)" -Level SUCCESS

        # Wait for VMs to register with host pool
        Write-Log "Waiting 60 seconds for session hosts to register with host pool..." -Level INFO
        Start-Sleep -Seconds 60

        # Verify registration
        Write-Log "Verifying session host registration..." -Level INFO
        $sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $HostPoolRG -HostPoolName $HostPoolName -ErrorAction SilentlyContinue
        $registeredCount = ($sessionHosts | Where-Object { $_.Status -eq 'Available' }).Count
        Write-Log "Currently $registeredCount session host(s) available in host pool" -Level INFO

        return $deployedVMs

    } catch {
        Write-Log "ERROR: Failed to deploy new session hosts: $($_.Exception.Message)" -Level ERROR
        Write-Log "ERROR Details: $($_.Exception.InnerException.Message)" -Level ERROR
        throw
    }
}

# ============= MAIN EXECUTION =============
try {
    Write-Log "=== AVD IMAGE UPDATE DEPLOYMENT STARTED ===" -Level SUCCESS
    Write-Log "Host Pool: $HostPoolName in $HostPoolResourceGroup" -Level INFO
    Write-Log "Session Host RG: $SessionHostResourceGroup" -Level INFO
    Write-Log "New Image: $NewImageResourceId" -Level INFO
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

    # Get domain join credentials
    $domainJoinCred = $null
    if ($isAzureAutomation) {
        Write-Log "Retrieving domain join credentials from Azure Automation..." -Level INFO
        $domainJoinCred = Get-AutomationPSCredential -Name $DomainJoinCredentialName
        if (-not $domainJoinCred) {
            throw "Failed to retrieve domain join credentials from Azure Automation. Ensure credential '$DomainJoinCredentialName' exists."
        }
        Write-Log "Domain join credentials retrieved successfully" -Level SUCCESS
    } else {
        Write-Log "Local execution - domain join credentials required" -Level WARNING
        Write-Log "Please enter domain join credentials:" -Level INFO
        $domainJoinCred = Get-Credential -Message "Enter domain join credentials"
    }

    # === STEP 1: SEND USER NOTIFICATIONS ===
    Write-Log "=== STEP 1: NOTIFYING USERS ===" -Level INFO
    $usersNotified = Send-UserNotifications -HostPoolRG $HostPoolResourceGroup `
        -HostPoolName $HostPoolName `
        -Message $UserNotificationMessage

    if ($usersNotified -gt 0) {
        if (-not $WhatIfMode) {
            Write-Log "Waiting $UserNotificationTimeMinutes minutes for users to log off..." -Level INFO
            Start-Sleep -Seconds ($UserNotificationTimeMinutes * 60)
        }

        # === STEP 2: ENABLE DRAIN MODE ===
        Write-Log "=== STEP 2: ENABLING DRAIN MODE ===" -Level INFO
        $sessionHosts = Enable-DrainMode -HostPoolRG $HostPoolResourceGroup -HostPoolName $HostPoolName

        # === STEP 3: LOG OFF ALL USERS ===
        Write-Log "=== STEP 3: LOGGING OFF ALL USERS ===" -Level INFO
        Disconnect-AllUserSessions -HostPoolRG $HostPoolResourceGroup `
            -HostPoolName $HostPoolName `
            -MaxWaitMinutes $MaxWaitForLogoffMinutes
    } else {
        Write-Log "No active users found - skipping notification wait, drain mode, and logoff steps" -Level INFO
    }

    # === STEP 4: REMOVE SESSION HOSTS FROM POOL ===
    Write-Log "=== STEP 4: REMOVING SESSION HOSTS FROM POOL ===" -Level INFO
    $vmNames = Remove-SessionHostsFromPool -HostPoolRG $HostPoolResourceGroup -HostPoolName $HostPoolName

    # === STEP 5: DELETE VMS AND RESOURCES ===
    Write-Log "=== STEP 5: DELETING VMS AND RESOURCES ===" -Level INFO
    Remove-SessionHostVMs -ResourceGroup $SessionHostResourceGroup `
        -VMNames $vmNames `
        -DeleteDisks $DeleteOldDisks

    # === STEP 6: DEPLOY NEW SESSION HOSTS ===
    Write-Log "=== STEP 6: DEPLOYING NEW SESSION HOSTS ===" -Level INFO
    $newVMs = Deploy-NewSessionHosts -HostPoolRG $HostPoolResourceGroup `
        -HostPoolName $HostPoolName `
        -SessionHostRG $SessionHostResourceGroup `
        -ImageId $NewImageResourceId `
        -VMNamePrefix $VMNamePrefix `
        -Count $NumberOfInstances `
        -VMSize $VMSize `
        -VNetRG $VNetResourceGroup `
        -VNetName $VNetName `
        -SubnetName $SubnetName `
        -DomainJoinCredential $domainJoinCred `
        -DomainFQDN $DomainName `
        -OUPath $OUPath

    Write-Log "=== AVD IMAGE UPDATE COMPLETED SUCCESSFULLY ===" -Level SUCCESS
    Write-Log "Old VMs removed: $($vmNames -join ', ')" -Level INFO
    if (-not $WhatIfMode) {
        Write-Log "New VMs deployed: $($newVMs -join ', ')" -Level INFO
    }

} catch {
    Write-Log "OPERATION FAILED: $($_.Exception.Message)" -Level ERROR

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
