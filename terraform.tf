terraform {
  required_version = ">= 1.9"

  # Backend configuration for remote state management
  # IMPORTANT: Uncomment and configure for production use to avoid local state files
  # You can use the backend_config variable values or customize as needed
  # 
  # backend "azurerm" {
  #   resource_group_name  = "terraform-state-rg"        # var.backend_config.resource_group_name
  #   storage_account_name = "tfstatexxxxxxx"            # var.backend_config.storage_account_name (must be globally unique)
  #   container_name       = "tfstate"                   # var.backend_config.container_name
  #   key                  = "azure-landing-zone.tfstate" # var.backend_config.key
  # }
  #
  # To enable remote backend:
  # 1. Create storage account and container manually or use Azure CLI
  # 2. Uncomment the backend block above
  # 3. Update storage_account_name to be globally unique
  # 4. Run: terraform init -migrate-state

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0, < 5.0.0"
    }
    modtm = {
      source  = "azure/modtm"
      version = "~> 0.3"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 1.14.0, < 3.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.4"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    alz = {
      source  = "Azure/alz"
      version = "~> 0.17"
    }
  }
}

provider "azurerm" {
  subscription_id = var.infra_subscription_id != null ? var.infra_subscription_id : var.management_subscription_id
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azurerm" {
  alias           = "management"
  subscription_id = var.management_subscription_id
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azurerm" {
  alias           = "connectivity"
  subscription_id = var.connectivity_subscription_id
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azurerm" {
  alias           = "identity"
  subscription_id = var.identity_subscription_id != null ? var.identity_subscription_id : var.management_subscription_id
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azurerm" {
  alias           = "avd"
  subscription_id = var.avd_subscription_id != null ? var.avd_subscription_id : var.management_subscription_id
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azurerm" {
  alias           = "aib"
  subscription_id = var.aib_subscription_id != null ? var.aib_subscription_id : var.management_subscription_id
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azurerm" {
  alias           = "infra"
  subscription_id = var.infra_subscription_id != null ? var.infra_subscription_id : var.management_subscription_id
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}


provider "modtm" {
  enabled = var.enable_telemetry
}

provider "alz" {
  library_references = [
    {
      path = "platform/alz"
      ref  = "2025.02.0"
    },
    {
      custom_url = "${path.root}/modules/core/lib"
    }
  ]
}
