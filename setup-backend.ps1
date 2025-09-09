# Azure Landing Zone - Backend Setup Script
# This script helps set up an Azure Storage backend for Terraform state

# =============================================================================
# BACKEND CONFIGURATION - Customize these values before running
# =============================================================================

# Location for backend resources
$Location = "UK South"

# Backend resource names following module naming conventions
# Format: rg-{environment}-{service}-{location_abbr}-{suffix}
$ResourceGroupName = "rg-shared-tfstate-uks"

# Storage account name (max 24 chars, lowercase, no special chars)
# Format: st{environment}{service}{random_suffix}
# Note: Change the suffix (last 6 chars) to ensure global uniqueness
$RandomSuffix = -join ((97..122) | Get-Random -Count 6 | ForEach-Object {[char]$_})
$StorageAccountName = "stprodtfstate$RandomSuffix"

# Container name for Terraform state
$ContainerName = "tfstate"

# State file key
$StateKey = "prod.tfstate"

# =============================================================================
# END CONFIGURATION
# =============================================================================

Write-Host "🚀 Setting up Azure Storage backend for Terraform..." -ForegroundColor Green
Write-Host "📍 Location: $Location"
Write-Host "📦 Resource Group: $ResourceGroupName"
Write-Host "💾 Storage Account: $StorageAccountName"
Write-Host "📁 Container: $ContainerName"
Write-Host ""

# Check if Azure CLI is installed and logged in
try {
    $null = Get-Command az -ErrorAction Stop
    Write-Host "✅ Azure CLI found" -ForegroundColor Green
}
catch {
    Write-Host "❌ Azure CLI is not installed. Please install it first." -ForegroundColor Red
    exit 1
}

try {
    $null = az account show 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Not logged in"
    }
    Write-Host "✅ Azure CLI is ready" -ForegroundColor Green
}
catch {
    Write-Host "❌ Not logged into Azure CLI. Please run 'az login' first." -ForegroundColor Red
    exit 1
}

# Create resource group
Write-Host "📦 Creating resource group..." -ForegroundColor Yellow
try {
    $null = az group create --name $ResourceGroupName --location $Location --output none
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Resource group created/updated: $ResourceGroupName" -ForegroundColor Green
    } else {
        throw "Failed to create resource group"
    }
}
catch {
    Write-Host "❌ Failed to create resource group" -ForegroundColor Red
    exit 1
}

# Create storage account
Write-Host "💾 Creating storage account..." -ForegroundColor Yellow
try {
    $null = az storage account create `
        --resource-group $ResourceGroupName `
        --name $StorageAccountName `
        --sku "Standard_LRS" `
        --encryption-services "blob" `
        --https-only true `
        --min-tls-version "TLS1_2" `
        --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Storage account created: $StorageAccountName" -ForegroundColor Green
    } else {
        throw "Failed to create storage account"
    }
}
catch {
    Write-Host "❌ Failed to create storage account (name might not be unique)" -ForegroundColor Red
    exit 1
}

# Create container
Write-Host "📁 Creating container..." -ForegroundColor Yellow
try {
    $null = az storage container create `
        --name $ContainerName `
        --account-name $StorageAccountName `
        --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Container created: $ContainerName" -ForegroundColor Green
    } else {
        throw "Failed to create container"
    }
}
catch {
    Write-Host "❌ Failed to create container" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🎉 Backend setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "📝 Next steps:" -ForegroundColor Cyan
Write-Host "1. Update terraform.tf and uncomment the backend block"
Write-Host "2. Replace the backend configuration with:"
Write-Host ""
Write-Host 'backend "azurerm" {' -ForegroundColor White
Write-Host "  resource_group_name  = `"$ResourceGroupName`"" -ForegroundColor White
Write-Host "  storage_account_name = `"$StorageAccountName`"" -ForegroundColor White
Write-Host "  container_name       = `"$ContainerName`"" -ForegroundColor White
Write-Host "  key                  = `"$StateKey`"" -ForegroundColor White
Write-Host "}" -ForegroundColor White
Write-Host ""
Write-Host "3. Run: terraform init -migrate-state"
Write-Host ""
Write-Host "💡 Alternatively, use the backend_config variable in your tfvars:" -ForegroundColor Cyan
Write-Host ""
Write-Host "backend_config = {" -ForegroundColor White
Write-Host "  enabled              = true" -ForegroundColor White
Write-Host "  resource_group_name  = `"$ResourceGroupName`"" -ForegroundColor White
Write-Host "  storage_account_name = `"$StorageAccountName`"" -ForegroundColor White
Write-Host "  container_name       = `"$ContainerName`"" -ForegroundColor White
Write-Host "  key                  = `"$StateKey`"" -ForegroundColor White
Write-Host "}" -ForegroundColor White
Write-Host ""
Write-Host "🔒 Backend storage details (save these for your team):" -ForegroundColor Cyan
Write-Host "Location: $Location"
Write-Host "Resource Group: $ResourceGroupName"
Write-Host "Storage Account: $StorageAccountName"
Write-Host "Container: $ContainerName"