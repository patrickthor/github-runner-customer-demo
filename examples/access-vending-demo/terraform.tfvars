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

# ------------------------------------------------------------------------------
# NOT HERE: enable_access_packages
#
# Whether catalogs and access packages get deployed is the `components` choice on
# the Deploy Identity Governance workflow:
#
#   groups-and-pim                   groups + RBAC + PIM policies
#   groups-pim-and-access-packages   the above, plus catalogs and access packages
#
# The workflow sets TF_VAR_enable_access_packages from that choice, and a TF_VAR
# always beats this file — so a copy here could never take effect. One source, so
# there is nothing to reconcile. Running locally without the variable gives
# groups + PIM only, which is the variable's default in variables.tf.
# ------------------------------------------------------------------------------

# Catalog label for scopes that do not set `catalog` themselves. A catalog is a
# DELEGATION boundary in Entra: whoever holds a catalog role can add resources and
# manage every package in it. Track ownership with it, not environment.
default_catalog = "cloud-access"

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

    # Omitted, so this scope lands in the default catalog "cloud-access".
    # One word here is all it takes to move it somewhere else.
    # catalog = "platform"

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
  # plus aws-sandbox-approvers, because "admin" uses approval_type = "dual".
  # ============================================================================

  "sandbox" = {
    cloud = "aws"

    # Its own catalog, so it can be delegated separately later — a sandbox is the
    # obvious first thing to hand to a team, and nothing else has to move.
    catalog = "sandboxes"

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

      # MFA, 4-hour cap. Eligibility has no forced expiry here — the access
      # package owns that lifecycle.
      #
      # "dual" rather than "owner", and NOT only because AdministratorAccess on an
      # AWS account deserves two signatures. It is load-bearing for the access
      # package:
      #
      #   * "dual" is what makes the access-vending module create
      #     aws-sandbox-approvers for this scope.
      #   * Both roles in this scope are pim_for_groups, so both are
      #     "EligibleMember", which the azuread provider cannot express — they are
      #     excluded from the package and finished in the portal.
      #   * Without an approver group, the sandbox package would therefore grant
      #     NOTHING. The access-packages module fails the plan on that rather than
      #     publishing a package that looks like working access and is not.
      #
      # With "dual", the package grants peer-approval rights in the scope, which is
      # also what stops this scope's single systemeier from deadlocking: PIM blocks
      # self-approval, so one owner cannot approve their own activation.
      "admin" = {
        jit_mechanism                           = "pim_for_groups"
        target_role                             = "AdministratorAccess"
        approval_type                           = "dual"
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
  #
  # 5. Give it its own catalog if you do enable it. Terraform enforces no
  #    activation rules here, so gate 1 — one systemeier approval on the access
  #    package — is the ENTIRE control. A separate catalog makes that visible in a
  #    listing instead of buried among harmless packages.
  # ============================================================================

  # "tenant" = {
  #   cloud      = "entra"
  #   catalog    = "directory-roles"        # keep it out of cloud-access
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

# ==============================================================================
# ACCESS PACKAGES — gate 1
#
# Ignored entirely under `components: groups-and-pim`, and committed anyway. The
# shape is then reviewable before the packages are ever live, and switching the
# workflow to groups-pim-and-access-packages needs no commit at all.
#
# Nothing below names a group, a role or a scope's contents. All of that comes from
# access_scopes above, through the access-vending module's contract. Adding a role
# up there gives it a package down here with no change to this section.
# ==============================================================================

# ------------------------------------------------------------------------------
# Catalogs — keyed on the LABEL used by scopes above
#
# Every key is optional. Both labels appear here only to name them properly; drop
# either block and it still works with the label as its display name.
# ------------------------------------------------------------------------------
catalogs = {

  "cloud-access" = {
    display_name = "Cloud Access"
    description  = "Terraform-vended access to Azure subscriptions. Membership is not privilege here — PIM activation is."

    # true, because the people who consume this access are B2B GUESTS in this
    # tenant, not member users.
    #
    # This is the first of two gates an external user has to clear. Entra checks
    # catalog visibility BEFORE it evaluates the assignment policy, so with this
    # false a guest sees nothing in My Access no matter what requestor_scope_type
    # says — and nothing anywhere reports why. The second gate is
    # requestor_scope_type below, which must also include guests.
    #
    # What this does NOT do: it does not let anyone outside the directory request.
    # A guest must already be invited and have accepted. Users with no account here
    # would need AllExternalSubjects or a connected organization, neither of which
    # is configured.
    externally_visible = true

    # Left false. Delegation is a standing grant, and standing grants are the
    # default no in this setup. Turn it on when a platform team should own its own
    # packages, and prefer "Access package manager" over "Catalog owner" — a
    # catalog owner can add arbitrary resources, which routes around access
    # vending entirely.
    delegate_to_systemeier = false
  }

  "sandboxes" = {
    display_name = "Sandbox Access"
    description  = "AWS sandbox accounts. Group membership itself is activated through PIM for Groups."

    # Same reason as cloud-access. Per catalog, not global — so a catalog that
    # genuinely should stay internal can be left false without affecting the rest.
    externally_visible = true

    # The sandbox is the obvious first thing to delegate, so this is where it
    # would go first. Still off until someone decides to.
    delegate_to_systemeier  = false
    systemeier_catalog_role = "Access package manager"
  }
}

# ------------------------------------------------------------------------------
# Gate 1 defaults — applied to every package unless a scope overrides them
# ------------------------------------------------------------------------------
access_package_defaults = {

  # 14 days. Short durations are this setup's substitute for access reviews: the
  # assignment expires and the user asks again, in a request that leaves a record.
  #
  # Must stay at or below the per-role ceiling in `terraform output
  # assignment_ceilings`. The sandbox admin role sets P15D, so anything above 15
  # days there would let PIM expire the eligibility while the package still lists
  # the user as assigned. The module fails the plan rather than allowing it.
  assignment_duration_days = 14

  # AllExistingDirectorySubjects, not AllExistingDirectoryMemberUsers.
  #
  #   AllExistingDirectoryMemberUsers   member users only — EXCLUDES guests
  #   AllExistingDirectorySubjects      members AND guests already in the directory
  #
  # The systemeier here are guests (userType "Guest", the #EXT# UPNs above), so the
  # member-only scope made every package invisible to the only people meant to use
  # them. Nothing failed: the packages applied cleanly, showed as published in the
  # portal, and simply did not appear in My Access.
  #
  # Broader options exist and are deliberately NOT used: AllExternalSubjects lets
  # anyone outside the directory request, and the connected-organization scopes
  # require a configured partner tenant. This is the narrowest value that includes
  # the actual users.
  #
  # SpecificDirectorySubjects would be narrower still, but the access-package
  # module emits no `requestor` block — the policy would be scoped to specific
  # subjects with none listed, so NOBODY could request. Passes validation, grants
  # nothing. Do not use it until the module supports named requestors.
  requestor_scope_type  = "AllExternalSubjects"
  require_justification = true

  # Gate 1 only. Gate 2 — PIM activation — has its own fixed 24-hour timeout that
  # nothing in either module can change.
  approval_timeout_days = 7

  # grant_approver_group used to live here. It is now REJECTED by the module —
  # approver rights are their own access package, configured in approver_packages
  # below. `terraform output peer_approval_status` still reports where a lone
  # systemeier would otherwise deadlock.
}

# ------------------------------------------------------------------------------
# Per-PACKAGE deviations from access_package_defaults. Keyed on package name.
#
# EMPTY, deliberately. Now that `access_packages` below declares packages
# explicitly, the same fields are available directly on each package block — so
# setting them here as well would mean two places configure one package with no
# obvious precedence.
#
# Keep this empty while packages are declared by hand. It earns its keep on the
# default path, where packages are generated per scope and there is no block to
# write the deviation into.
# ------------------------------------------------------------------------------
access_package_overrides = {}

# ------------------------------------------------------------------------------
# Named packages — LEFT EMPTY, so behaviour is one package per scope.
#
# Uncomment to split a scope into audiences. A package grants everything in it
# atomically, so this is the only way to say "engineers get reader and contributor,
# admins also get owner" on one subscription.
#
# It does NOT give the two audiences different activation rules on `contributor`.
# Azure keys the activation policy on (scope, role), so both share one policy and
# its MFA, duration and approvers. Only gate 1 — who may request, for how long,
# approved by whom — differs per package.
#
# Any role no package names is reported in `terraform output unpackaged_roles`
# rather than silently dropped, so splitting a scope will flag what you forgot.
# ------------------------------------------------------------------------------
access_packages = {

  # Engineers: permanent read, plus the ability to activate Contributor. No Owner.
  "platform-engineers" = {
    display_name = "Platform Engineer Access"
    description  = "Day-to-day work on the platform subscription. Contributor is activated through PIM, not held."

    role_keys = [
      "platform-demo--reader",
      "platform-demo--contributor",
    ]

    # No approver rights are attached here any more, and none can be: the approver
    # group is a separate package. An engineer who should also be able to approve
    # requests the approver package on top of this one.

    # 180 days, NOT the 14-day default. A reviewed package needs a duration longer
    # than its review interval — quarterly is 90 — or the assignment expires before
    # the first campaign runs and the review has an empty subject list. The module
    # fails the plan on that rather than letting it look like governance.
    #
    # This IS a loosening compared with 14-day expiry, and the review is what pays
    # for it. Reader is permanent but read-only; Contributor still requires PIM
    # activation with dual approval every time.
    assignment_duration_days = 180

    access_reviews = {
      review_frequency = "quarterly"
      review_type      = "Reviewers" # the scope's systemeier
      duration_in_days = 14          # how long each campaign stays open
      timeout_behavior = "removeAccess"

      approver_justification_required = true
    }
  }

  # Admins: everything the engineers get, plus Owner.
  "platform-admins" = {
    display_name = "Platform Admin Access"
    description  = "Elevated access to the platform subscription, including the ability to activate Owner."

    role_keys = [
      "platform-demo--reader",
      "platform-demo--contributor",
      "platform-demo--owner",
    ]

    # 60 days with a MONTHLY review, rather than 7-day expiry. Reviewed monthly is a
    # stronger control than expiring weekly: expiry only proves someone still wants
    # the access, a review makes a named systemeier confirm they should have it.
    #
    # 60 rather than 31 because the duration must exceed the 30-day review interval,
    # and a value close to the interval means a campaign can open days before the
    # assignment lapses anyway.
    assignment_duration_days = 60

    # Holding this package no longer confers approver rights either. That is the
    # point of the split: an admin who should be able to approve peers requests the
    # platform-demo approver package as well, and that grant expires on its own
    # schedule.

    # Monthly, because this is the package that can reach Owner.
    access_reviews = {
      review_frequency = "monthly"
      review_type      = "Reviewers"
      duration_in_days = 14
      timeout_behavior = "removeAccess"

      approver_justification_required = true
    }
  }

  # Named explicitly because `access_packages` is no longer empty: once ANY package
  # is declared, the per-scope default no longer applies and every role must be
  # named by some package. Leave this out and both aws-sandbox-* groups show up in
  # `terraform output unpackaged_roles` — vended, but unrequestable.
  "sandbox" = {
    display_name = "Sandbox Access"

    role_keys = [
      "sandbox--readonly",
      "sandbox--admin",
    ]

    # sandbox-admin sets active_assignment_expire_after = "P15D", so the package
    # assignment must not outlive it. 14 would pass; 10 leaves headroom if someone
    # tightens the PIM policy later without reading this file. The module fails the
    # plan rather than allowing the drift.
    assignment_duration_days = 10
    question_text            = "Which sandbox account, and what are you testing?"

    # Under contract v2 both roles ARE attachable: the vending module creates a plain
    # eligibility-carrier group per pim_for_groups role, and this package grants plain
    # Member on those carriers. The user then activates the real, PIM-managed
    # membership. Before v2 this package granted only the approver group, because
    # EligibleMember cannot be set from Terraform.

    # NO access_reviews BLOCK HERE, deliberately — presence would mean on.
    #
    # Expiry is this package's recurring control, and the two are alternatives rather
    # than complements. It also cannot have one as configured: sandbox-admin sets
    # active_assignment_expire_after = "P15D", which caps the assignment at 15 days, so
    # every review interval except weekly is longer than the assignment can live. The
    # module rejects that combination and points at the vending config, because the fix
    # is to raise active_assignment_expire_after in access_scopes above — trading a
    # longer standing eligibility window for a review that someone has to action.
    #
    # Left as-is so the demo shows both models side by side: platform-* reviewed,
    # sandbox expiring.
  }
}

# ------------------------------------------------------------------------------
# APPROVER PACKAGES — one per scope, granting only that scope's approver group.
#
# EMPTY, which is the working default: an approver package is created for every
# scope that has an approver group, i.e. every scope with a role using
# approval_type = "dual". Here that is both platform-demo and sandbox.
#
# Requesting one of these is how a person gains the right to approve OTHER people's
# PIM activations in that scope. It grants no access itself. Gate 1 on it is always
# the scope's systemeier — approvers cannot appoint approvers, or the chain would
# have no terminating authority.
#
# This replaced `grant_approver_group`, which bolted the approver group onto the
# access package. That forced the approver population to equal the requester
# population and made it impossible to approve without holding the access. The
# module now rejects the old field rather than reinterpreting it.
#
# Add an entry only to deviate. `enabled = false` opts a scope out entirely, which
# leaves the systemeier as the only approvers there.
# ------------------------------------------------------------------------------
access_approver_packages = {

  "platform-demo" = {
    display_name = "Platform Approver Rights"
    description  = "The right to approve other people's PIM activations on the platform subscription. Grants no access of its own."

    # 180 days. Approving is a standing duty rather than a task, and re-requesting it
    # monthly would be friction with no security value — the grant confers no access.
    # The recurring control is the review below, not expiry.
    #
    # Approver packages have no PIM expiry ceiling (they contain only the approver
    # group, which is not a pim_for_groups role), so a long duration paired with a
    # review is available here in a way it is not for the sandbox access package.
    assignment_duration_days = 180

    # Quarterly, and arguably the most important review in the configuration: this
    # grant is standing and it confers authority over everyone else's activations.
    access_reviews = {
      review_frequency = "quarterly"
      review_type      = "Reviewers"
      duration_in_days = 14
      timeout_behavior = "removeAccess"

      approver_justification_required = true
    }
  }

  "sandbox" = {
    display_name = "Sandbox Approver Rights"
    description  = "The right to approve activation of aws-sandbox-admin. Grants no access of its own."

    assignment_duration_days = 180

    access_reviews = {
      review_frequency = "quarterly"
      review_type      = "Reviewers"
      duration_in_days = 14
      timeout_behavior = "removeAccess"

      approver_justification_required = true
    }
  }

  # `enabled = false` on a scope opts it out entirely, leaving the systemeier as its
  # only approvers. Not used here — with one systemeier on sandbox, PIM's
  # self-approval block would make its "dual" role un-activatable by that person
  # alone. `terraform output peer_approval_status` reports exactly that.
}

# ------------------------------------------------------------------------------
# NOT HERE ANY MORE: manage_pim_for_groups_roles / acknowledge_m3_active_membership
#
# Both are rejected by the module now if set to anything at all, including false.
#
# They existed for the EligibleMember gap:
# azuread_access_package_resource_package_association validates access_type to
# "Member" and "Owner" only, so a PIM-managed group could not be attached to a
# package and had to be finished by hand in the portal. The two flags were the
# opt-in to attaching it as "Member" anyway, which silently converted
# just-in-time eligibility into standing access.
#
# Contract v2 removes the gap instead of working around it. The vending module
# creates a plain eligibility-carrier group per pim_for_groups role and makes it an
# eligible member of the PIM-managed group; the package grants plain Member on the
# carrier, and the user activates the real membership in PIM. Nothing is downgraded,
# so there is nothing left to acknowledge — and `manual_steps_required` should now
# come back empty.
# ------------------------------------------------------------------------------
