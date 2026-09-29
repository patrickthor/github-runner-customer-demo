terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4.0"
    }
  }
}

# AzureRM is required statically by the dual-mode Lighthouse module even though
# ARM mode creates and reads no Azure resources. The workflow authenticates this
# provider to the subscription containing the artifact storage account.
provider "azurerm" {
  features {}

  subscription_id = var.artifact_storage_subscription_id
}
