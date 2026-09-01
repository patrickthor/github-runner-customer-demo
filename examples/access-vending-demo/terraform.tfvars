# ==============================================================================
# terraform.tfvars — DEMO CONFIGURATION. COMMIT THIS FILE.
#
# Unlike most Terraform templates, this file belongs in git. For an access-vending
# system the configuration IS the governance record: "who is systemeier for prod"
# and "which roles require dual approval" are exactly the changes that should
# arrive as a reviewed pull request with history. The repo .gitignore has an
# explicit exception for this path.
#
# tenant_id and provider_subscription_id are NOT here. They are provider
# configuration and come from GitHub secrets via TF_VAR_ — see the workflow.
#
# ------------------------------------------------------------------------------
# BEFORE YOU APPLY, replace:
#   * scope_id on "platform-demo" with a real subscription GUID
#   * every @example.com UPN with real users in your tenant
#
# The values below are valid Terraform and will pass `plan`, but they point at a
# placeholder subscription and users that do not exist, so `apply` will fail
# against a real tenant until you replace them.
#
# Full field reference: modules/access-vending/README.md in the source repo.
# ==============================================================================

# Default prefix when a scope does not set `cloud` itself.
cloud_prefix = "azure"

# false on purpose — a group owner can bypass the access package entirely, and
# because membership is managed outside Terraform the bypass never shows in a plan.
set_systemeier_as_group_owner = false

# Wait for Graph propagation before PIM resources are created on new groups.
pim_group_propagation_delay = "30s"

access_scopes = {

  # ============================================================================
  # AZURE SUBSCRIPTION — jit_mechanism "azure_pim" (the default, so omitted).
  #
  # The group is NOT PIM-managed; membership is active. The user activates the
  # ROLE. Requires cloud = "azure", azure_role, and scope_id as a subscription
  # GUID.
  #
  # Produces groups: azure-platform-demo-reader / -contributor / -owner
  # plus the approver group azure-platform-demo-approvers, seeded with the
  # systemeier so a "dual" role is activatable from the first apply.
  # ============================================================================

  "platform-demo" = {
    cloud = "azure"

    # REPLACE with a real subscription GUID before applying.
    scope_id = "3f1fc96d-69db-4cb6-93d3-0fa2eb9cd79e"

    # Two or more is strongly advised: an approver cannot approve their own
    # request, so a lone systemeier cannot activate their own "dual" role.
    systemeier = [
      "patrick.thor_bouvet.no#EXT#@t16rpocazl.onmicrosoft.com",
      "edgar.grane_bouvet.no#EXT#@t16rpocazl.onmicrosoft.com",
    ]

    roles = {
      # Permanent read. No activation, no approval. The time limit comes from
      # expiry on the access package assignment in the sister repo.
      "reader" = {
        azure_role       = "Reader"
        permanent_access = true
      }

      # Requires activation. "dual" = the systemeier AND the approver group
      # azure-platform-demo-approvers. One signature from either is enough.
      "contributor" = {
        azure_role            = "Contributor"
        approval_type         = "dual"
        max_activation_hours  = 8
        require_justification = true
      }

      # Highest privilege: MFA, short window, ticket reference.
      "owner" = {
        azure_role           = "Owner"
        approval_type        = "dual"
        max_activation_hours = 2
        require_mfa          = true
        require_ticket_info  = true
      }
    }
  }

  # ============================================================================
  # AWS ACCOUNT — jit_mechanism "pim_for_groups", must be explicit.
  #
  # The group IS PIM-managed: the access package grants eligibility and the user
  # activates the MEMBERSHIP.
  #
  # Terraform does NOT connect the group to AWS. Provision it there with SCIM
  # from the Entra enterprise application and bind it to the permission set.
  # `target_role` documents what that binding should be — see the output
  # target_cloud_bindings for the work list.
  #
  # Note the scope key is "sandbox", not "aws-sandbox": the prefix comes from
  # `cloud`, so "aws-sandbox" would produce aws-aws-sandbox-admin.
  #
  # Produces groups: aws-sandbox-readonly / aws-sandbox-admin
  # ============================================================================

  "sandbox" = {
    cloud = "aws"

    # Documentation only for pim_for_groups — no resource binds it.
    scope_id = "123456789012"

    systemeier = ["patrick.thor_bouvet.no#EXT#@t16rpocazl.onmicrosoft.com"]

    roles = {
      # Self-service activation, no approver.
      "readonly" = {
        jit_mechanism                  = "pim_for_groups"
        target_role                    = "ReadOnlyAccess"
        approval_type                  = "self"
        active_assignment_expire_after = "P30D"
      }

      # Approved by the systemeier, MFA, 4-hour cap. Eligibility has no forced
      # expiry here — the access package owns that lifecycle.
      "admin" = {
        jit_mechanism                           = "pim_for_groups"
        target_role                             = "AdministratorAccess"
        approval_type                           = "owner"
        max_activation_hours                    = 4
        require_mfa                             = true
        active_assignment_expire_after          = "P15D"
        eligible_assignment_expiration_required = false
      }
    }
  }

  # ============================================================================
  # ENTRA DIRECTORY ROLES — jit_mechanism "entra_role". LEFT DISABLED.
  #
  # Commented out on purpose. Enabling it is a tenant-wide privilege decision,
  # not a demo step:
  #
  # 1. Terraform CANNOT set MFA, approval or maximum duration for directory
  #    roles — the azuread provider has no policy resource for them. Those
  #    fields are REJECTED here rather than silently ignored. Set them in the
  #    PIM portal and check: terraform output entra_activation_governance_gap
  #
  # 2. It needs two extra Graph permissions that the other mechanisms do not:
  #    RoleManagement.ReadWrite.Directory and
  #    RoleEligibilitySchedule.ReadWrite.Directory. The first lets the identity
  #    assign directory roles anywhere in the tenant, INCLUDING TO ITSELF.
  #
  # 3. The role you vend has power over the other mechanisms. Groups
  #    Administrator can manage membership in every non-role-assignable group —
  #    all your azure_pim and pim_for_groups groups — and rewrite their PIM
  #    policies.
  #
  # 4. These groups are role-assignable, which is FORCE-REPLACE in Entra. They
  #    cannot be converted later or reused by the other mechanisms, so keep
  #    entra_role roles in their own scope.
  # ============================================================================

  # "tenant" = {
  #   cloud      = "entra"
  #   scope_id   = "/"                      # or "/administrativeUnits/<guid>"
  #   systemeier = ["demo.identityowner@example.com"]
  #
  #   roles = {
  #     "directoryreader" = {
  #       jit_mechanism    = "entra_role"
  #       entra_role       = "Directory Readers"
  #       permanent_access = true
  #     }
  #   }
  # }
}
