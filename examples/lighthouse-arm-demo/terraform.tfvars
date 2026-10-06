# ==============================================================================
# Azure Lighthouse ARM artifact governance record — COMMIT THIS FILE.
#
# This contains identifiers and authorization policy, not credentials. The
# managing tenant ID, storage coordinates, authentication, and artifact version
# are supplied by the publishing workflow.
#
# Empty is safe and produces no artifacts. Add one entry per customer delegation
# using the example below. UUIDs must identify security groups/users in the
# MANAGING tenant. Eligible principals should be groups, not service principals.
# ==============================================================================

customers = {
  "customer-a" = {
    offer_name        = "Customer A Platform Management"
    offer_description = "Delegated subscription management through Azure Lighthouse."
    principals = {
      platform_operators = {
        principal_id    = "33333333-3333-3333-3333-333333333333"
        principal_name  = "LH-CustomerA-PlatformOperators"
        permanent_roles = ["Reader"]
        eligible_roles = {
          Contributor = {
            maximum_activation_duration = "PT2H"
            require_mfa                 = true
            approvers = [{
              principal_id   = "44444444-4444-4444-4444-444444444444"
              principal_name = "LH-Platform-Approvers"
            }]
          }
        }
      }
    }
  }
}
