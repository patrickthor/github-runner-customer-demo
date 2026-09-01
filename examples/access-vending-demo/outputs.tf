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
