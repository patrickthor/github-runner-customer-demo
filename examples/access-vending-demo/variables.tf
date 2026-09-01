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
