# ==============================================================================
# Access vending demo — consuming the access-vending module
#
# Creates Entra groups, binds them to Azure RBAC / target-cloud roles, and sets
# the PIM activation rules. It grants NO humans access: it defines which access
# grants exist. Who can receive them is decided by the sister access-package
# repo, which looks the groups up BY NAME.
#
# Files:
#   main.tf            this file — the module call
#   variables.tf       declarations
#   versions.tf        provider blocks + backend
#   outputs.tf         the contract consumed by the access-package repo
#   terraform.tfvars   the access configuration — COMMITTED, see README
# ==============================================================================

module "access_vending" {
  # ALWAYS PIN A REF.
  #
  # The groups created here are looked up by NAME by the access-package repo. An
  # unintended upgrade that changes the naming convention breaks that link, and
  # the failure surfaces in the OTHER repo as "group does not exist" — not here.
  #
  # Pinned to a commit SHA rather than a tag because the source repo has no tags
  # yet; its only branch is `initial-setup`. Once a release is cut, switch this
  # to that tag — a SHA is immutable but tells you nothing about what changed.
  #
  #   SHA 442d028 — initial-setup @ 2026-09-01
  source = "github.com/patrickthor/terraform-azuread-access-vending-development//modules/access-vending?ref=442d028368a27f701477bfddfd2fa4f2f64d854e"

  access_scopes = var.access_scopes

  cloud_prefix                  = var.cloud_prefix
  group_description_template    = var.group_description_template
  set_systemeier_as_group_owner = var.set_systemeier_as_group_owner
  pim_group_propagation_delay   = var.pim_group_propagation_delay
}
