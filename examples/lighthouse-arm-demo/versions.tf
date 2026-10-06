terraform {
  required_version = ">= 1.9, < 2.0"

  # State for the dedicated artifact account lives in the existing internal
  # Terraform backend under its own key. Artifact blobs never use that account.
  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.0"
    }
  }
}

provider "azurerm" {
  features {}

  subscription_id     = var.artifact_storage_subscription_id
  storage_use_azuread = true
}
