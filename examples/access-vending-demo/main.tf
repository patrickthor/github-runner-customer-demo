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
# var.enable_access_packages gates the second module, and nothing else:
#
#   false  groups + PIM only. Gate 2 exists, nothing is requestable yet.
#   true   the full chain. Catalogs and access packages on top.
#
# It is set by the workflow's `components` choice, not by terraform.tfvars — a
# TF_VAR always beats a tfvars entry, so a copy there could never take effect.
#
#   groups-and-pim                   -> false
#   groups-pim-and-access-packages   -> true
#
# Switching back down after packages exist DESTROYS the catalogs and packages. The
# workflow reads that out of the plan and refuses the apply without an explicit
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
  # ALWAYS PIN AN IMMUTABLE REF.
  #
  # A commit SHA, because neither module repo has tags yet. Immutability is the
  # property that matters, but a SHA tells you nothing about what changed — so
  # switch BOTH pins to v1.0.0 once the tags are cut, and keep them in lockstep.
  # The two modules share a versioned contract (contract_version = 1), so a
  # mismatched pair fails with a type error rather than doing something subtly
  # wrong.
  #
  # A branch ref would be wrong even though `initial-setup` exists: these groups
  # are the resource identity the access packages attach to, so an unintended
  # module change can orphan every package association.
  #
  #   02e8533d — initial-setup @ 2026-09-10, "Update error message"
  #              (also carries "Upgrade azurerm to 5.x and stop committing lock
  #              files", so the module now requires azurerm >= 5.0 — which is why
  #              versions.tf here pins ~> 5.4.0.)
  source = "github.com/patrickthor/terraform-azuread-access-vending-development//modules/access-vending?ref=02e8533d04832560ecd5c8ec3504ffcc0452f412"

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
# reference to module.access_vending.contract has to exist even when this block is
# not instantiated. So an init failure naming a missing ref means the pin is wrong,
# in either mode.
# ------------------------------------------------------------------------------

module "access_packages" {
  count = var.enable_access_packages ? 1 : 0

  #   ccb1476d — inital-commit @ 2026-09-10, "support multi access package per
  #              subscription". This is the commit that renamed scope_overrides to
  #              package_overrides and added the `packages` input.
  source = "github.com/patrickthor/terraform-azuread-access-packages-development//modules/access-packages?ref=ccb1476db872d62fdde2bc5f68ca06a3ab2a41e0"

  # The whole taxonomy, in memory. Scope keys, role keys, group names, group
  # object IDs, access types, catalog labels, the systemeier lists and the
  # per-role assignment ceiling all come from here. Nothing about repo 1's
  # configuration is restated below.
  vending = module.access_vending.contract

  # Per-catalog settings, keyed on the catalog LABEL set in terraform.tfvars.
  # Every key is optional; a label with no entry gets the defaults.
  catalogs = var.catalogs

  # Request-side (gate 1) defaults, and per-package deviations from them.
  #
  # `package_overrides` was called `scope_overrides` before ccb1476d. The rename is
  # not cosmetic: the package is now the unit of everything in that module. On the
  # default path each scope still produces one package NAMED AFTER THE SCOPE, so
  # existing keys like "sandbox" keep matching and the values are unchanged.
  defaults          = var.access_package_defaults
  package_overrides = var.access_package_overrides

  # Named packages. Empty here, which keeps the default behaviour: one package per
  # scope containing every role in it.
  #
  # Set this when a single scope needs more than one audience. A package grants
  # everything in it atomically, so "engineers get reader+contributor, admins also
  # get owner" cannot be expressed by a scope-wide package — it needs two packages
  # over the same groups.
  #
  # Note what this is NOT for: giving two audiences DIFFERENT activation rules on
  # the same Azure role. Azure keys the activation policy on (scope, role), so
  # there is exactly one policy for Contributor on a subscription and both
  # audiences share its MFA, duration and approvers. That is also why the vending
  # module rejects two eligible azure_pim roles with the same azure_role on one
  # subscription — duplicating the role there would buy nothing.
  packages = var.access_packages

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
