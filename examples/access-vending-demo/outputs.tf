# ==============================================================================
# Outputs — the contract the access-package repo consumes
#
# The module exposes 22 outputs; these are the ones used downstream plus the
# four that exist for verification. See modules/access-vending/outputs.tf in the
# source repo for the rest.
# ==============================================================================

output "group_names" {
  description = "Group name per composite key '{scope}--{role}'. The access-package repo looks up on this string."
  value       = module.access_vending.group_names
}

output "group_object_ids" {
  description = "Entra object ID per composite key."
  value       = module.access_vending.group_object_ids
}

output "access_package_access_type" {
  description = "Member or EligibleMember per composite key. Set this on the resource role binding in the access-package repo."
  value       = module.access_vending.access_package_access_type
}

output "approver_group_names" {
  description = "Approver group per scope key. Only scopes with a 'dual' role appear here."
  value       = module.access_vending.approver_group_names
}

output "approver_group_object_ids" {
  description = "Entra object ID per approver group, keyed on scope."
  value       = module.access_vending.approver_group_object_ids
}

output "systemeier_by_scope" {
  description = "System owner UPNs per scope. Used as named approvers on the access package request gate."
  value       = module.access_vending.systemeier_by_scope
}

output "target_cloud_bindings" {
  description = "Work list for the cloud side: what SCIM must connect where. pim_for_groups only."
  value       = module.access_vending.target_cloud_bindings
}

# ------------------------------------------------------------------------------
# Verification
# ------------------------------------------------------------------------------

output "access_summary" {
  description = "One line per role: group name, mechanism, model, access. For reading a plan quickly."
  value       = module.access_vending.access_summary
}

output "approvers_by_role" {
  description = "Who approves activation, per composite key. Check this before testing activation."
  value       = module.access_vending.approvers_by_role
}

output "entra_activation_governance_gap" {
  description = "What Terraform does NOT control for entra_role. Empty if you do not use that mechanism."
  value       = module.access_vending.entra_activation_governance_gap
}

output "demo_eligibility_schedules" {
  description = "Should be empty. Values here mean standing eligibility outside the access package flow."
  value       = module.access_vending.demo_eligibility_schedules
}

# ==============================================================================
# The contract between the two modules
#
# This is what module "access_packages" consumes. Exposed as an output so the
# hand-off is inspectable — when something is wrong downstream, this is the first
# thing to read, and in groups+PIM-only mode it is how you see what the packages
# WOULD be built from before enabling them.
#
# Not sensitive on its own: group names, object IDs, catalog labels and systemeier
# UPNs. The state file already holds all of it.
# ==============================================================================

output "contract" {
  description = "Everything module \"access_packages\" needs: contract_version, roles keyed '{scope}--{role}', scopes keyed '{scope}', and catalogs keyed on label."
  value       = module.access_vending.contract
}

output "catalog_labels" {
  description = "Catalog label per scope key. One catalog is created (or adopted) per distinct label."
  value       = { for k, s in module.access_vending.contract.scopes : k => s.catalog }
}

output "assignment_ceilings" {
  description = <<-EOT
    Per composite key, the maximum access-package assignment duration in days
    implied by the group's PIM policy. null means no ceiling.

    Only pim_for_groups roles have one. Exceeding it makes PIM expire the
    eligibility while the package still lists the user as assigned — they lose
    access without losing the assignment, and nothing errors.
  EOT
  value = {
    for k, r in module.access_vending.contract.roles : k => r.max_assignment_days
    if r.max_assignment_days != null
  }
}

# ==============================================================================
# Access packages — null in groups+PIM-only mode
#
# one() rather than try(): it returns null for a count = 0 module and errors on a
# genuinely missing output, so a renamed output in the module fails here instead of
# quietly reading as "packages disabled".
# ==============================================================================

output "access_packages_enabled" {
  description = "Whether catalogs and access packages are part of this configuration."
  value       = var.enable_access_packages
}

output "catalogs" {
  description = "Catalog label to catalog ID, display name, and whether it was created here or adopted. null when access packages are disabled."
  value       = one(module.access_packages[*].catalogs)
}

output "packages_by_catalog" {
  description = <<-EOT
    Which access packages landed in which catalog. null when disabled.

    A catalog is a delegation boundary — whoever holds a catalog role can manage
    every package in it — so this listing is security-relevant, not cosmetic.
  EOT
  value       = one(module.access_packages[*].packages_by_catalog)
}

output "granted_groups_by_package" {
  description = "What each package actually grants, after EligibleMember exclusions. Compare against contract.roles to see what is missing."
  value       = one(module.access_packages[*].granted_groups_by_package)
}

output "gate_1_approvers" {
  description = "Per package, the systemeier acting as named approvers on the request. Gate 1 decides who may enter a scope at all."
  value       = one(module.access_packages[*].gate_1_approvers)
}

output "peer_approval_status" {
  description = "Where the single-systemeier activation deadlock is resolved by peer approval and where it is not. A lone systemeier cannot approve their own request, and the PIM timeout is a fixed 24 hours."
  value       = one(module.access_packages[*].peer_approval_status)
}

# ------------------------------------------------------------------------------
# The two outputs that matter more than the apply succeeding
# ------------------------------------------------------------------------------

output "manual_steps_required" {
  description = <<-EOT
    What Terraform could NOT do, with the portal path for each item. Read this
    before believing an apply.

    Expected to be non-empty whenever the configuration has pim_for_groups roles:
    the azuread provider cannot express "Eligible Member" on a resource role, so
    those attachments are finished by hand.
  EOT
  value       = one(module.access_packages[*].manual_steps_required)
}

output "excluded_resource_roles" {
  description = "Per-group detail behind manual_steps_required: which groups are registered as catalog resources but not attached to their package, and what access type they need."
  value       = one(module.access_packages[*].excluded_resource_roles)
}
