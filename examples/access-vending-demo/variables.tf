# ==============================================================================
# Variables
#
# Two groups:
#
#   1. tenant_id and provider_subscription_id — provider configuration only.
#      Supplied by CI as TF_VAR_* from GitHub secrets, so real identifiers stay
#      out of the committed terraform.tfvars.
#
#   2. access_scopes and the rest — the access configuration, which DOES live in
#      the committed terraform.tfvars. See README for why.
# ==============================================================================

# ------------------------------------------------------------------------------
# Provider configuration — from secrets, not from tfvars
# ------------------------------------------------------------------------------

variable "tenant_id" {
  description = <<-EOT
    Entra tenant ID. Used only by the azuread provider.

    Set by CI as TF_VAR_tenant_id from the AZURE_TENANT_ID secret. Locally,
    export TF_VAR_tenant_id or pass -var.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "provider_subscription_id" {
  description = <<-EOT
    Subscription the azurerm provider authenticates against.

    Role bindings use an explicit scope per subscription, so this only needs to
    point at one subscription the identity can reach — not necessarily the one
    being vended.

    Required even with no azure_pim roles: azurerm needs a provider block
    because of features {}, and that block must be configurable even when the
    configuration creates no azurerm resources.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.provider_subscription_id))
    error_message = "provider_subscription_id must be a GUID."
  }
}

# ------------------------------------------------------------------------------
# Access configuration — from the committed terraform.tfvars
# ------------------------------------------------------------------------------

variable "access_scopes" {
  description = <<-EOT
    Access scopes and their roles.

    The type is `any` on purpose. The module owns the type definition and its 30+
    validations; repeating the schema here would be ~180 lines guaranteed to
    drift from the module's copy, and the module is the one that enforces it.

    Practical effect: an error in terraform.tfvars is reported against
    module.access_vending rather than this root. The message is identical.

    Full field reference: modules/access-vending/README.md in the source repo.
  EOT
  type        = any
  default     = {}
}

variable "cloud_prefix" {
  description = "Default prefix on group names when a scope does not set `cloud` itself. Lowercase letters and digits only."
  type        = string
  default     = "azure"
}

variable "default_catalog" {
  description = <<-EOT
    Catalog label for scopes that do not set `catalog` themselves.

    The access-vending module creates no catalogs. It validates the label and
    forwards it in its contract; the access-packages module creates or adopts one
    catalog per distinct label. So adding a catalog is one word on a scope in
    terraform.tfvars, with no code change on either side.

    A catalog in Entra is a DELEGATION boundary — who may add resources to it and
    manage packages inside it. Track ownership with it, not environment. One
    identity team owning everything means one catalog is correct.
  EOT
  type        = string
  default     = "cloud-access"
}

variable "group_description_template" {
  description = <<-EOT
    Template for the group description. Placeholders: {cloud}, {sub}, {role},
    {target_role}, {scope_id}. null gives each mechanism its own default, which
    names the correct JIT model.
  EOT
  type        = string
  default     = null
}

variable "set_systemeier_as_group_owner" {
  description = <<-EOT
    Whether the systemeier are set as owners on the role groups. Default false,
    deliberately.

    A group owner can manage membership directly and so bypass the access
    package entirely — and because membership is managed outside Terraform, such
    a bypass would never appear in a plan.

    false does NOT mean "no owners": Graph makes the identity running Terraform
    the owner of every group it creates, and that cannot be removed. Run apply as
    a service principal, never as a user.
  EOT
  type        = bool
  default     = false
}

variable "pim_group_propagation_delay" {
  description = <<-EOT
    Wait before PIM resources are created on newly created groups, so they can
    propagate in Graph. Applies to the pim_for_groups and entra_role mechanisms.
  EOT
  type        = string
  default     = "30s"
}

# ==============================================================================
# Access packages — the second module
#
# Everything below is unused under `components: groups-and-pim`. Declared
# unconditionally so that switching to the full chain requires no edit here, and so
# a reviewer can see the whole intended shape in one file.
# ==============================================================================

variable "enable_access_packages" {
  description = <<-EOT
    Whether to create catalogs and access packages on top of the groups and PIM
    policies.

      false  groups + PIM only. Gate 2 exists; nothing is requestable yet, so no
             user can obtain access without being added to a group by hand.

      true   the full chain. Catalogs, access packages and assignment policies.

    SET BY THE WORKFLOW, NOT BY terraform.tfvars. The Deploy Identity Governance
    workflow's `components` choice exports TF_VAR_enable_access_packages, and a
    TF_VAR always beats a tfvars entry — so keeping a copy in terraform.tfvars
    would be a value that can never take effect. The switch has exactly one home.

      groups-and-pim                   -> false
      groups-pim-and-access-packages   -> true

    Default false so a local `terraform plan` without the variable does the
    smaller, safer thing.

    Before deploying packages: eligible group membership in access packages needs
    Entra ID Governance or Entra Suite, NOT P2 alone, and a P2-only tenant fails
    partway through the apply rather than at plan. Run
    scripts/verify-entitlement-management.sh from the access-packages repo first.

    Switching back down after packages exist DESTROYS the catalogs and access
    packages. The workflow refuses that apply without an explicit confirmation
    input.
  EOT
  type        = bool
  default     = false
}

variable "catalogs" {
  description = <<-EOT
    Per-catalog settings, keyed on the catalog LABEL used by scopes in
    access_scopes.

    Every key is optional — a label with no entry here gets the defaults, so the
    single-catalog case needs nothing at all. A key that does not match a label
    actually in use is REJECTED rather than ignored: an override with no effect is
    a change you believe you made and did not.

    Fields, all optional:
      display_name              defaults to the label
      description
      externally_visible        default false. Set true when the people who
                                consume the access are B2B GUESTS rather than
                                member users. Entra checks catalog visibility
                                BEFORE the assignment policy, so false hides every
                                package in the catalog from guests regardless of
                                requestor_scope_type, and reports nothing. It does
                                not admit anyone outside the directory — a guest
                                must already be invited and have accepted.
      published                 default true. False makes the catalog's packages
                                non-requestable without deleting them.
      adopt_existing            default false. True looks the catalog up instead
                                of creating it, for customers whose identity team
                                owns catalog creation.
      delegate_to_systemeier    default false. True gives the scope's systemeier a
                                catalog role, so package management sits with the
                                people who already approve gate 1. Off by default
                                because it is a standing grant.
      systemeier_catalog_role   default "Access package manager". Prefer it over
                                "Catalog owner": a catalog owner can add arbitrary
                                resources, which routes around access-vending
                                entirely.

    The type is `any` for the same reason as access_scopes: the module owns the
    schema and its validations, and repeating them here would guarantee drift.
  EOT
  type        = any
  default     = {}
}

variable "access_package_defaults" {
  description = <<-EOT
    Gate 1 (request-side) settings applied to every access package unless a scope
    overrides them.

    Defaults fail safe: approval is always required and the assignment expires on
    its own. Forgetting a field gives you more control, not less.

    Fields, all optional:
      assignment_duration_days  how long an approved assignment lasts. Short
                                durations are this setup's substitute for access
                                reviews: it expires and the user asks again. Must
                                stay at or below the per-role ceiling the
                                access-vending contract reports as
                                max_assignment_days, or Entitlement Management and
                                PIM drift apart — PIM expires the eligibility
                                while the package still lists the user as
                                assigned. The module enforces this at plan time.
      requestor_scope_type      who may request. The module default is
                                AllExistingDirectoryMemberUsers, which is MEMBER
                                USERS ONLY and excludes guests. Use
                                AllExistingDirectorySubjects for members and
                                guests. Note that SpecificDirectorySubjects passes
                                validation but grants nothing: the module emits no
                                `requestor` block, so the policy ends up scoped to
                                specific subjects with none listed.
      require_justification     default true.
      approval_timeout_days     gate 1 timeout only. Gate 2 (PIM activation) has
                                its own fixed 24-hour timeout that nothing here
                                can change.
      grant_approver_group      default true. Also grants the scope's approver
                                group through the package, making everyone in the
                                scope a peer approver. This is what fixes the
                                single-systemeier deadlock: PIM blocks
                                self-approval, so a lone systemeier cannot
                                activate their own "dual" role and the request
                                times out.
  EOT
  type        = any
  default     = {}
}

variable "access_package_scope_overrides" {
  description = <<-EOT
    Per-scope deviations from access_package_defaults, keyed on scope key. Omitted
    fields fall back to the defaults.

    Every key must match a scope that actually exists in access_scopes. A typo is
    rejected, not silently ineffective.
  EOT
  type        = any
  default     = {}
}

variable "manage_pim_for_groups_roles" {
  description = <<-EOT
    Whether to attach roles whose access type is "EligibleMember" to their package
    anyway, downgraded to "Member".

    Default false. Those roles are then left out of Terraform and listed in the
    module's excluded_resource_roles and manual_steps_required outputs. Their
    CATALOG associations are still created, so finishing them by hand is one click
    on an already-registered resource rather than a full registration.

    Why the gap exists: azuread_access_package_resource_package_association
    validates access_type to "Member" and "Owner" only. The provider builds the
    Graph role scope as "{access_type}_{group_object_id}", so the sole barrier is a
    client-side allowlist — not a missing API. The Entra portal does offer
    "Eligible Member" for PIM-managed groups.

    Setting this true trades just-in-time for full IaC coverage: the user becomes
    an ACTIVE member the moment the assignment lands, with standing access to the
    target cloud. That is a security regression, so it additionally requires
    acknowledge_m3_active_membership = true.
  EOT
  type        = bool
  default     = false
}

variable "acknowledge_m3_active_membership" {
  description = <<-EOT
    Explicit acknowledgement that manage_pim_for_groups_roles converts
    just-in-time eligibility into standing active membership.

    Two flags instead of one because the failure mode is invisible: the apply
    succeeds, the portal looks correct, and the only symptom is that users hold
    access they should have had to activate for.
  EOT
  type        = bool
  default     = false
}
