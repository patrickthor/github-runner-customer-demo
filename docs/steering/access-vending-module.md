---
inclusion: always
---

# Repo 1 — access-vending

Read `identity-governance-contract.md` first. This file covers only what is local to this
repo.

## What this repo owns

Entra groups, their Azure RBAC bindings, their target-cloud role documentation, and their
PIM activation policies — **gate 2**. It grants no human anything. It defines *which*
access grants exist.

## What this repo must never do

- Create a catalog, an access package, or an assignment policy.
- Assign a human to a group. Membership comes from repo 2's access package. The one
  exception is `demo_eligible_user_principal_names`, which is an escape hatch that must
  stay empty outside a demo and is blocked in CI.
- Set `set_systemeier_as_group_owner = true` by default. A group owner manages membership
  directly and so bypasses the access package entirely — and because membership is
  managed outside Terraform, the bypass never appears in a plan. For `pim_for_groups` it
  is worse: a directly added member is *active*, not eligible, so it skips activation,
  approval and MFA in one step.
- Know what a catalog is. `catalog` is an opaque label this repo validates and forwards.

## Changes to land for the two-module contract

Everything below is **additive**. The existing 22 outputs stay; they are good for reading
a plan. What changes is that the *machine* contract becomes a single object.

### 1. `catalog` label on each scope

```hcl
variable "default_catalog" {
  description = <<-EOT
    Catalog label applied to scopes that do not set `catalog` themselves.

    This repo creates no catalogs. The label is forwarded in `contract.scopes[*].catalog`
    and in `contract.catalogs`, and repo 2 creates or adopts one catalog per distinct
    label. Keeping it here means adding a catalog is one word in the shared
    terraform.tfvars rather than a second source of truth in repo 2.
  EOT
  type        = string
  default     = "cloud-access"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.default_catalog))
    error_message = "default_catalog must be lowercase letters, digits and hyphens."
  }
}
```

Add to the `access_scopes` object type, next to `cloud`:

```hcl
catalog = optional(string)
```

Validate the same character set. **Declaring the field explicitly is not optional.**
Terraform silently drops unknown attributes when converting to an object type, so a
`catalog` in `terraform.tfvars` that this repo has not declared would simply vanish with
no error — the same trap that `approver_group_name` is declared at role level purely to
reject.

### 2. Derive `max_assignment_days`

Repo 1 owns `active_assignment_expire_after`, so repo 1 emits the ceiling as a number and
nobody parses ISO-8601:

```hcl
locals {
  expire_after_days = {
    P15D  = 15
    P30D  = 30
    P90D  = 90
    P180D = 180
    P365D = 365
  }
}
```

`"permanent"` maps to `null`. `azure_pim` and `entra_role` map to `null` — the trap only
exists for `pim_for_groups`. This replaces repo 2's hand-set `m3_max_duration_days`
variable, which is deleted.

### 3. The `contract` output

One output, shape defined in the shared contract file. Two implementation rules:

**Assemble keys from `var.access_scopes`, never from resource attributes.** Group names
happen to be plan-known today because `display_name` is an input, but that is luck. Build
`roles`, `scopes`, `catalogs`, `role_keys` and `scope_keys` from the variable, and take
only `group_object_id` from the modules. If a future change makes a key depend on a
resource attribute, repo 2's plan breaks — for a change made here.

**Do not `merge(...)` unknown-keyed maps into contract keys.** The existing outputs merge
across the three mechanism submodules with `merge([...]...)`. That is fine for human
outputs. For `contract`, iterate `var.access_scopes` directly and look the object ID up
per mechanism, so the key set provably comes from configuration.

Keep the naming formula in the submodules. `contract.roles[*].group_name` reads it back
from them; it is not recalculated in the root. One place only.

### 4. Cut `v1.0.0`

The only branch is `initial-setup` and there are no tags. The customer config pins a tag,
and a branch pin is a review finding. Tag after the contract lands, and tag repo 2 to
match.

## Validations to add

| Check | Why |
|---|---|
| `catalog` matches `^[a-z0-9-]+$` when set | It becomes a map key in the contract and a display-name component in repo 2. |
| A scope whose only roles are `entra_role` gets a warning-level note in an output, not a rejection, if it shares a catalog with other scopes | Directory-role packages are the highest-privilege thing in the system and should be easy to spot in a catalog listing. Not fatal — a customer may legitimately want one catalog. |
| `contract_version` is a literal, not derived | It has to be greppable. |

Do not add a validation that a catalog label is "used". A label with no scopes cannot
exist, since the label lives on the scope.

## Existing invariants worth not breaking

These are already right. Changing them breaks repo 2 or the customer.

- **`--` is reserved** and validated out of scope keys and role keys. Repo 2 splits on it.
- **Role key `approvers` is reserved**, because the approver group is
  `{cloud}-{scope}-approvers` and a role with that key would collide. This is also what
  guarantees `"{scope}--approvers"` is free as a resource-role label in repo 2.
- **`approver_group_*` outputs are keyed on scope**, not composite key. One approver group
  serves every role under a scope.
- **Approver groups exist only where some role uses `approval_type = "dual"`.** Repo 2
  must tolerate a scope with no approver group.
- **Approver groups are seeded with the scope's `systemeier`** so a `dual` role is
  activatable from the first apply. This is also what creates the single-systemeier
  deadlock repo 2 fixes with peer approval, so it is worth a comment pointing at
  repo 2 rather than "fixing" it here.
- **`azurerm_role_management_policy` is keyed on (ARM scope, role)**, not per group, so
  two eligible `azure_pim` roles cannot share an `azure_role` on the same
  `scope_id` — across different scope *keys* too. The existing validation catches this;
  keep the `scope_id`-based comparison.
- **Group renames are destructive.** Renaming a scope key or role key destroys and
  recreates the group, which orphans everything repo 2 attached to it. Say so in the
  field reference.

## Irreversibility to keep documented

- **PIM onboarding cannot be undone.** Once a group is managed by PIM it stays managed.
  Deleted groups can linger in the PIM for Groups list for up to 24 hours, so re-applying
  the same group names shortly after a destroy hits friction.
- **`azuread_directory_role` does nothing on destroy.** Directory roles activated by the
  `entra_role` mechanism stay activated in the tenant after `terraform destroy`.
- **Role-assignable groups are force-replace.** `assignable_to_role` cannot be flipped
  later, so keep `entra_role` roles in their own scope.

## Where to look

- `modules/access-vending/README.md` — the field reference. Keep it authoritative; the
  customer README links to it rather than restating fields.
- `modules/access-vending/modules/*/README.md` — one per mechanism, including the SCIM
  hand-off for `pim_for_groups`.
- `bootstrap/grant-graph-permissions.sh` — idempotent, skips what is already granted.
  Add `EntitlementManagement.ReadWrite.All` to it so one script covers both modules.
