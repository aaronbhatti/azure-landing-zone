terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
      configuration_aliases = [
        azurerm.spoke,
        azurerm.connectivity
      ]
    }
    modtm = {
      source  = "Azure/modtm"
      version = "~> 0.3"
    }
  }
}