terraform {
  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = "~> 4.0"
      configuration_aliases = [azurerm.connectivity]
    }
    modtm = {
      source  = "azure/modtm"
      version = "~> 0.3"
    }
  }
}
