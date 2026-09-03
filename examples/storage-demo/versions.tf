terraform {
  required_version = ">= 1.5"

  # Remote state, matching runner-demo and access-vending-demo.
  #
  # This example runs on ephemeral ACI runners, so local state disappeared with
  # the container: every run started empty, each apply leaked a new resource
  # group, and destroy could never remove anything. Remote state fixes all three
  # and makes a repeat run prove idempotency.
  #
  # It uses its own container, separate from the other two configurations. The
  # runner identity is granted data access to that container only — see the
  # "Provision runner state container" step in deploy-runners.yml.
  #
  # The workflow generates backend.hcl. Locally:
  #   terraform init -backend-config=backend.hcl
  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.63"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
