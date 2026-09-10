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
    # 5.x, and `~>` rather than `>=`. The old `>= 4.63` had no upper bound, so a
    # fresh init would float into whatever major is current — which is exactly how
    # a provider upgrade arrives without anyone choosing it.
    #
    # This config uses only azurerm_resource_group and azurerm_storage_account.
    # Checked against the 5.0 breaking changes:
    #
    #  * min_tls_version no longer accepts TLS1_0/TLS1_1 — this sets TLS1_2, fine.
    #  * the queue_properties and static_website blocks were removed — not used.
    #  * allow_nested_items_to_be_public now defaults to false instead of true.
    #    Not set here, so expect a one-time in-place update on the first 5.x apply.
    #    It tightens the account rather than loosening it.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
  }
}
