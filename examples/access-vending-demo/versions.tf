# ==============================================================================
# Providers, backend and version requirements
#
# Provider configuration lives HERE, in the root — not in the module. A reusable
# module with its own provider blocks cannot be used with count, for_each or
# depends_on, so the access-vending module deliberately has none.
#
# Constraints use `~>` here. The module itself uses `>=` so it never becomes a
# ceiling for consumers; a root configuration has a lockfile and a single owner,
# so pinning is safe and desirable.
#
# required_version >= 1.9 is a HARD floor: the module's validations use
# cross-variable references, a 1.9 feature. On 1.5-1.8 the configuration fails
# with "Invalid reference in variable validation" before anything else runs.
# ==============================================================================

terraform {
  required_version = ">= 1.9"

  # ----------------------------------------------------------------------------
  # Remote state — REQUIRED, and a deliberate difference from storage-demo.
  #
  # storage-demo uses local state because it is a throwaway test: losing the
  # state just orphans a resource group. This configuration is different. It
  # creates PERSISTENT Entra groups that another repo references by name, and it
  # runs on ephemeral ACI runners whose filesystem disappears with the container.
  # With local state, every run would start empty and try to recreate groups that
  # already exist.
  #
  # The workflow generates backend.hcl from GitHub variables. Locally:
  #   terraform init -backend-config=backend.hcl
  #
  # State contains subscription IDs, group object IDs, UPNs and full PIM policy
  # content in plaintext. Use a storage account with RBAC, not access keys.
  # ----------------------------------------------------------------------------
  backend "azurerm" {}

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.9.0"
    }

    # Declared here even though this configuration never references it directly.
    #
    # The access-vending module pulls it in for time_sleep, which is what lets a
    # newly created group propagate in Graph before PIM resources are written to
    # it. The module constrains it to `>= 0.12` with no upper bound — correct for a
    # reusable module, which must not become a ceiling for consumers, but it means
    # nothing bounds the major version unless a root does.
    #
    # With no lockfile committed, this block IS the bound. Without it, the provider
    # that gates PIM onboarding resolves to whatever is newest, forever.
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.0"
    }
    # 5.x. This configuration creates no azurerm resources directly — they all
    # live in the access-vending module, which uses four: data
    # azurerm_role_definition, azurerm_role_assignment,
    # azurerm_role_management_policy and azurerm_pim_eligible_role_assignment.
    # None was removed or breaking-changed in 5.0.
    #
    # Two reasons to be on 5.x rather than 4.x:
    #
    #  * azurerm_role_assignment.description is no longer ForceNew (5.2.0). On 4.x,
    #    editing group_description_template destroyed and recreated every permanent
    #    Azure role binding — a real loss of live access from a cosmetic change.
    #  * resource_provider_registrations now defaults to "none" instead of
    #    "legacy", so the provider no longer walks ~60 resource-provider
    #    registrations on startup. This config only needs Microsoft.Authorization,
    #    which is always registered.
    #
    # ONE LANDMINE, not currently triggered: the azurerm_role_definition DATA
    # SOURCE's `role_definition_id` attribute now returns a bare UUID instead of a
    # Resource Manager ID. The module reads `.id`, which is still the ARM ID, so it
    # is unaffected — but role_management_policy and pim_eligible_role_assignment
    # both need the scoped ARM ID, so switching to the same-named
    # `role_definition_id` attribute would silently pass the wrong thing. Use the
    # new `role_definition_resource_id` (5.3.0) if you want it unambiguous.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4.0"
    }
  }
}

provider "azuread" {
  tenant_id = var.tenant_id
}

provider "azurerm" {
  # features {} is required by azurerm even when the configuration creates no
  # azurerm resources. A pure pim_for_groups setup still needs it.
  features {}

  # Role bindings use an explicit scope per subscription, so this only needs to
  # be a subscription the identity can authenticate against.
  subscription_id = var.provider_subscription_id
}
