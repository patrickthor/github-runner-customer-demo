# ==============================================================================
# Azure Lighthouse ARM artifact test matrix — COMMIT THIS FILE.
#
# This contains demo identifiers and authorization policy, not credentials. The
# managing tenant ID, storage coordinates, authentication, and artifact version
# are supplied by the publishing workflow.
#
# Every map entry renders one self-contained SUBSCRIPTION-SCOPE ARM template.
# Azure Lighthouse onboarding requires a separate deployment per subscription,
# so a customer with two subscription scopes appears twice. The customer chooses
# the target subscription when uploading the generated template in Azure Portal.
#
# All UUIDs below are synthetic demo values. Before deploying an artifact, replace
# principal_id and approver IDs with real security-group/user object IDs from the
# MANAGING tenant. Eligible principals must not be service principals.
#
# Logical customers: 5 (A-E)
# Generated subscription artifacts: 6 (Customer E has two scopes)
# ==============================================================================

customers = {
  # ---------------------------------------------------------------------------
  # Customer A — baseline production-style pattern
  #
  # Permanent Reader is required so the group can discover the delegated scope
  # and activate eligible Contributor. Contributor requires MFA, one approver,
  # and a two-hour activation window.
  # ---------------------------------------------------------------------------
  "customer-a" = {
    offer_name        = "Customer A Platform Management"
    offer_description = "Baseline delegated subscription management with approved JIT Contributor."

    principals = {
      platform_operators = {
        principal_id    = "33333333-3333-4333-8333-333333333333"
        principal_name  = "LH-CustomerA-PlatformOperators"
        permanent_roles = ["Reader"]

        eligible_roles = {
          Contributor = {
            maximum_activation_duration = "PT2H"
            require_mfa                 = true

            approvers = [{
              principal_id   = "44444444-4444-4444-8444-444444444444"
              principal_name = "LH-CustomerA-Approvers"
            }]
          }
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Customer B — multiple principals and multiple roles in one delegation
  #
  # Two operator groups receive the same eligible Contributor role. Lighthouse
  # requires every instance of the same eligible role in one definition to use
  # identical JIT policy, so both deliberately share duration, MFA and approver.
  # A separate audit group is Reader-only. A delegation-administrator group gets
  # Reader plus the narrowly scoped delegation-removal role.
  # ---------------------------------------------------------------------------
  "customer-b" = {
    offer_name        = "Customer B Shared Operations"
    offer_description = "Multiple operational teams, read-only auditors, and delegated removal authority."

    principals = {
      platform_operators = {
        principal_id    = "55555555-5555-4555-8555-555555555551"
        principal_name  = "LH-CustomerB-PlatformOperators"
        permanent_roles = ["Reader"]

        eligible_roles = {
          Contributor = {
            maximum_activation_duration = "PT4H"
            require_mfa                 = true

            approvers = [{
              principal_id   = "77777777-7777-4777-8777-777777777777"
              principal_name = "LH-CustomerB-Approvers"
            }]
          }
        }
      }

      application_operators = {
        principal_id    = "55555555-5555-4555-8555-555555555552"
        principal_name  = "LH-CustomerB-ApplicationOperators"
        permanent_roles = ["Reader"]

        # Must remain byte-for-byte equivalent to platform_operators' Contributor
        # policy. The module rejects inconsistent policy for the same eligible role.
        eligible_roles = {
          Contributor = {
            maximum_activation_duration = "PT4H"
            require_mfa                 = true

            approvers = [{
              principal_id   = "77777777-7777-4777-8777-777777777777"
              principal_name = "LH-CustomerB-Approvers"
            }]
          }
        }
      }

      security_auditors = {
        principal_id    = "66666666-6666-4666-8666-666666666666"
        principal_name  = "LH-CustomerB-SecurityAuditors"
        permanent_roles = ["Reader"]
      }

      delegation_administrators = {
        principal_id   = "99999999-9999-4999-8999-999999999999"
        principal_name = "LH-CustomerB-DelegationAdministrators"
        permanent_roles = [
          "Reader",
          "Managed Services Registration Assignment Delete Role",
        ]
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Customer C — self-service JIT at the minimum duration
  #
  # No approvers means the operator may activate without approval. MFA remains
  # required, and PT30M exercises the shortest supported activation window.
  # ---------------------------------------------------------------------------
  "customer-c" = {
    offer_name        = "Customer C On-Demand Support"
    offer_description = "Short self-service Contributor activation protected by MFA."

    principals = {
      support_engineers = {
        principal_id    = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        principal_name  = "LH-CustomerC-SupportEngineers"
        permanent_roles = ["Reader"]

        eligible_roles = {
          Contributor = {
            maximum_activation_duration = "PT30M"
            require_mfa                 = true
            approvers                   = []
          }
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Customer D — self-service JIT without Lighthouse MFA, maximum duration
  #
  # This intentionally exercises multiFactorAuthProvider=None and PT8H, the
  # longest supported window. It is a capability test, not the recommended
  # production posture; managing-tenant Conditional Access must still apply.
  # ---------------------------------------------------------------------------
  "customer-d" = {
    offer_name        = "Customer D Extended Operations"
    offer_description = "Maximum-duration Contributor activation with MFA delegated to tenant policy."

    principals = {
      operations = {
        principal_id    = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        principal_name  = "LH-CustomerD-Operations"
        permanent_roles = ["Reader"]

        eligible_roles = {
          Contributor = {
            maximum_activation_duration = "PT8H"
            require_mfa                 = false
            approvers                   = []
          }
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Customer E — first of two subscription scopes: platform
  #
  # One Lighthouse definition cannot onboard two subscriptions. These two entries
  # therefore generate separate artifacts for the same logical customer and reuse
  # the same managing-tenant operator group. The platform scope also tests two
  # independent approver groups.
  # ---------------------------------------------------------------------------
  "customer-e-platform" = {
    offer_name        = "Customer E Platform Subscription"
    offer_description = "Platform subscription delegation with two managing-tenant approver groups."

    principals = {
      cloud_operators = {
        principal_id    = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        principal_name  = "LH-CustomerE-CloudOperators"
        permanent_roles = ["Reader"]

        eligible_roles = {
          Contributor = {
            maximum_activation_duration = "PT2H"
            require_mfa                 = true

            approvers = [
              {
                principal_id   = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
                principal_name = "LH-CustomerE-PlatformApprovers"
              },
              {
                principal_id   = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
                principal_name = "LH-CustomerE-SecurityApprovers"
              },
            ]
          }
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Customer E — second subscription scope: connectivity
  #
  # Reuses the operator group but has a separate offer identity, artifact and JIT
  # policy. The customer deploys this JSON against the connectivity subscription.
  # ---------------------------------------------------------------------------
  "customer-e-connectivity" = {
    offer_name        = "Customer E Connectivity Subscription"
    offer_description = "Connectivity subscription delegation with a shorter activation window."

    principals = {
      cloud_operators = {
        principal_id    = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        principal_name  = "LH-CustomerE-CloudOperators"
        permanent_roles = ["Reader"]

        eligible_roles = {
          Contributor = {
            maximum_activation_duration = "PT1H"
            require_mfa                 = true

            approvers = [{
              principal_id   = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
              principal_name = "LH-CustomerE-PlatformApprovers"
            }]
          }
        }
      }
    }
  }
}
