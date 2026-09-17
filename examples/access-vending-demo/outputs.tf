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

    Only pim_for_groups roles have one, and it comes from the PIM-MANAGED group's
    active_assignment_expire_after — not from the eligibility carrier the package
    actually grants. Exceeding it makes PIM expire the eligibility while the package
    still lists the user as assigned: they lose the ability to activate without
    losing the assignment, and nothing errors.
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
    Catalog label to { package name = access package ID }. null when disabled.

    A catalog is a delegation boundary — whoever holds a catalog role can manage
    every package in it — so this listing is security-relevant, not cosmetic.
  EOT
  value       = one(module.access_packages[*].packages_by_catalog)
}

output "packages" {
  description = <<-EOT
    Every access package that was built, keyed on package name, with the scope and
    role keys behind it.

    On the default path — var.access_packages empty — there is one package per scope
    and the package names ARE the scope keys. Read this after defining named
    packages, to confirm the split landed the way you meant.
  EOT
  value       = one(module.access_packages[*].packages)
}

output "approver_packages" {
  description = <<-EOT
    Per scope, the approver package that grants that scope's approver group.

    Requesting one of these confers the right to approve OTHER people's PIM
    activations in the scope, and grants no access itself. Gate 1 on it is always the
    scope's systemeier. A scope with `enabled = false` in
    var.access_approver_packages does not appear here, which means the systemeier are
    its only approvers.
  EOT
  value       = one(module.access_packages[*].approver_packages)
}

output "unpackaged_roles" {
  description = <<-EOT
    Roles present in the contract that NO package grants. Should be empty.

    Only reachable once var.access_packages is set: naming packages explicitly means
    a role can be left out, and a vended group nobody can request is access that
    exists on paper and cannot be obtained. Reported here rather than silently
    dropped.
  EOT
  value       = one(module.access_packages[*].unpackaged_roles)
}

output "granted_groups_by_package" {
  description = <<-EOT
    What each package actually grants, keyed on package name.

    For pim_for_groups roles the group named here is the plain ELIGIBILITY CARRIER,
    not the PIM-managed group. Membership of the carrier is what the package hands
    out; it confers eligibility to activate the PIM-managed group named alongside it.
    The carrier itself carries no access — if anything is ever bound to it, every
    member holds standing access and PIM is bypassed.
  EOT
  value       = one(module.access_packages[*].granted_groups_by_package)
}

output "gate_1_approvers" {
  description = "Per package name, the systemeier acting as named approvers on the request. Gate 1 decides who may enter a scope at all. A package cannot span scopes, so these always come from a single scope's systemeier."
  value       = one(module.access_packages[*].gate_1_approvers)
}

output "peer_approval_status" {
  description = "Where the single-systemeier activation deadlock is resolved by peer approval and where it is not. Keyed on SCOPE, not package — it describes gate 2, which the vending module owns. `granted_by_packages` shows which packages hand out the scope's approver group. A lone systemeier cannot approve their own request, and the PIM timeout is a fixed 24 hours."
  value       = one(module.access_packages[*].peer_approval_status)
}

output "access_reviews_enabled" {
  description = "Whether recurring access reviews are part of this configuration. Driven by the workflow's deploy_access_reviews checkbox, not by terraform.tfvars."
  value       = var.enable_access_reviews
}

output "access_reviews" {
  description = <<-EOT
    Per package, the effective review settings, the resolved reviewers, and whether the
    review is actually deployed.

    `deployed = false` means the configuration exists but enable_access_reviews is off,
    so no review block was written to the assignment policy. Read this rather than
    inferring from the presence of configuration.
  EOT
  value       = one(module.access_packages[*].access_reviews)
}

output "access_reviews_configured_not_deployed" {
  description = <<-EOT
    Packages that have review configuration while the master switch is off. Should be
    empty once reviews are deployed.

    This is the state most likely to be misread as "reviews are on" — the tfvars say
    quarterly, the portal shows none. Non-empty here means tick
    `deploy_access_reviews` on the workflow.
  EOT
  value       = one(module.access_packages[*].access_reviews_configured_not_deployed)
}

# ------------------------------------------------------------------------------
# The two outputs that matter more than the apply succeeding
# ------------------------------------------------------------------------------

output "manual_steps_required" {
  description = <<-EOT
    What Terraform could NOT do, with the portal path for each item. Read this
    before believing an apply.

    EXPECTED EMPTY under contract v2. It used to list every pim_for_groups role,
    because the azuread provider cannot set "Eligible Member" on a resource role —
    the eligibility carrier groups remove that gap. A non-empty list now means
    something genuinely could not be expressed, so read it rather than assuming it is
    the old known issue.
  EOT
  value       = one(module.access_packages[*].manual_steps_required)
}

output "excluded_resource_roles" {
  description = "Per-group detail behind manual_steps_required: groups registered as catalog resources but not attached to their package. Expected empty under contract v2 — the eligibility carrier groups mean pim_for_groups roles no longer need the EligibleMember access type."
  value       = one(module.access_packages[*].excluded_resource_roles)
}
