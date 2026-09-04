# ==============================================================================
# Identity governance demo — two modules, one state
#
#   module "access_vending"    WHICH access grants exist
#                              Entra groups + Azure RBAC + PIM activation policies
#                              This is gate 2: who may activate what, and how.
#
#   module "access_packages"   WHO can receive them
#                              Catalogs + access packages + assignment policies
#                              This is gate 1: who may enter a scope at all.
#
# Both read the same committed terraform.tfvars. Values flow between them in
# memory through module.access_vending.contract — no remote state read, no group
# lookup by name, and no second copy of the scope/role taxonomy.
#
# ------------------------------------------------------------------------------
# WHY ONE STATE AND NOT TWO
#
# The access packages must not be created before the PIM policies exist. Not only
# because the groups have to be there: for pim_for_groups roles it is the act of
# writing the PIM policy that ONBOARDS the group to PIM for Groups, and until that
# has happened the platform does not offer "Eligible Member" as a resource role at
# all. Attaching the group anyway gives standing membership instead of
# just-in-time, and nothing fails.
#
# With one state that ordering is a dependency in the graph. With two states it is
# a pipeline convention someone can get wrong, and the symptom is silent.
#
# The cost is a shared blast radius: `terraform destroy` here removes the
# governance and the packages together. That is the trade. It is acceptable partly
# because the two modules already have to run as the SAME identity —
# azuread_access_package_resource_catalog_association fails with
# CallerNotResourceOwner unless the caller owns the group being linked, and
# repo 1's identity owns every group it creates.
#
# ------------------------------------------------------------------------------
# TWO DEPLOY MODES
#
# var.enable_access_packages gates the second module:
#
#   false  groups + PIM only. Gate 2 exists, nothing is requestable yet. Useful
#          for standing up the tenant, verifying group naming, and testing
#          activation with a hand-added member before any package exists.
#
#   true   the full chain. Catalogs and access packages on top.
#
# The workflow can narrow a run to groups+PIM without editing this file, but it
# CANNOT quietly widen or narrow the committed intent — see the guard in
# deploy-access-vending.yml. Turning this off after packages exist is a DESTROY of
# the catalogs and packages, which the workflow refuses without an explicit
# confirmation input.
#
# Files:
#   main.tf            this file — the module calls
#   variables.tf       declarations
#   versions.tf        provider blocks + backend
#   outputs.tf         verification surface for both modules
#   terraform.tfvars   the governance record — COMMITTED, see README
# ==============================================================================

# ------------------------------------------------------------------------------
# Module 1 — groups, RBAC bindings, PIM policies
# ------------------------------------------------------------------------------

module "access_vending" {
  # ALWAYS PIN A TAG.
  #
  # Both modules are pinned to the same tag on purpose: they share a versioned
  # contract (contract_version 1), and a mismatched pair fails with a type error
  # rather than doing something subtly wrong. Keeping the versions in lockstep
  # makes the pairing obvious to a reviewer.
  source = "github.com/patrickthor/terraform-azuread-access-vending-development//modules/access-vending?ref=v1.0.0"

  access_scopes = var.access_scopes

  cloud_prefix                  = var.cloud_prefix
  default_catalog               = var.default_catalog
  group_description_template    = var.group_description_template
  set_systemeier_as_group_owner = var.set_systemeier_as_group_owner
  pim_group_propagation_delay   = var.pim_group_propagation_delay
}

# ------------------------------------------------------------------------------
# Module 2 — catalogs, access packages, assignment policies
#
# count rather than a separate configuration, so both modes share one state and
# one tfvars. Note that `count = 0` still requires the module source to RESOLVE at
# init: Terraform fetches every declared module regardless of count, and the
# reference to module.access_vending.contract must exist even when this block is
# not instantiated. Both repos must therefore be tagged before either mode works.
# ------------------------------------------------------------------------------

module "access_packages" {
  count = var.enable_access_packages ? 1 : 0

  source = "github.com/patrickthor/terraform-azuread-access-packages-development//modules/access-packages?ref=v1.0.0"

  # The whole taxonomy, in memory. Scope keys, role keys, group names, group
  # object IDs, access types, catalog labels, the systemeier lists and the
  # per-role assignment ceiling all come from here. Nothing about repo 1's
  # configuration is restated below.
  vending = module.access_vending.contract

  # Per-catalog settings, keyed on the catalog LABEL set in terraform.tfvars.
  # Every key is optional; a label with no entry gets the defaults.
  catalogs = var.catalogs

  # Request-side (gate 1) defaults and per-scope deviations.
  defaults        = var.access_package_defaults
  scope_overrides = var.access_package_scope_overrides

  # Roles whose access type is "EligibleMember" cannot be expressed by the
  # azuread provider — access_type is validated to Member/Owner only. Left false,
  # so those roles are excluded from Terraform and reported in
  # manual_steps_required instead of being silently downgraded to standing
  # membership. See the README before changing either flag.
  manage_pim_for_groups_roles      = var.manage_pim_for_groups_roles
  acknowledge_m3_active_membership = var.acknowledge_m3_active_membership

  # Belt and braces. The reference to module.access_vending.contract already
  # creates the dependency, but PIM onboarding is the ordering that matters most
  # here and it is worth being unmissable to a reader.
  depends_on = [module.access_vending]
}
