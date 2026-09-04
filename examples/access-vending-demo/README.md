# Identity Governance Demo — groups, PIM, catalogs and access packages

Two modules, one state, one committed `terraform.tfvars`, running on the self-hosted ACI runners provisioned by this repo.

| Module | Repo | Creates | Gate |
|---|---|---|---|
| `access_vending` | [terraform-azuread-access-vending](https://github.com/patrickthor/terraform-azuread-access-vending-development) | Entra groups, Azure RBAC bindings, PIM activation policies | **Gate 2** — who may activate what, and how |
| `access_packages` | [terraform-azuread-access-packages](https://github.com/patrickthor/terraform-azuread-access-packages-development) | catalogs, access packages, assignment policies | **Gate 1** — who may enter a scope at all |

```
terraform.tfvars  (the governance record, committed)
        │
        ├──► module "access_vending"     WHICH access grants exist
        │         group + role binding + PIM policy
        │         └── output "contract" ──┐
        │                                 │  in memory, same apply
        └──► module "access_packages" ◄───┘
                  catalog + access package + assignment policy
                  WHO can receive them
```

## Why one state

The packages must not exist before the PIM policies. Not only because the groups have to be there: for `pim_for_groups` roles it is the act of writing the PIM policy that **onboards the group to PIM for Groups**, and until that has happened the platform does not offer "Eligible Member" as a resource role at all. Attach the group anyway and you get standing membership instead of just-in-time, with nothing failing.

With one state that ordering is an edge in the dependency graph. With two states it is a convention someone can get wrong, and the symptom is silent.

It also means no `terraform_remote_state`, no cross-state RBAC grant, and no second copy of the scope/role taxonomy — the packages module never writes a group name or a scope key.

The cost is a shared blast radius: `terraform destroy` here removes governance and packages together. Acceptable partly because the two modules already have to run as the **same identity** — `azuread_access_package_resource_catalog_association` fails with `CallerNotResourceOwner` unless the caller owns the group being linked, and the vending identity owns every group it creates.

## The two gates

Two approval points answering different questions. Neither module implements the other's.

```
request package → [GATE 1] → assigned / eligible → activate in PIM → [GATE 2] → active access
```

| | Gate 1 — request the package | Gate 2 — activate |
|---|---|---|
| Question | *Should this person have access to this scope at all?* | *Should they hold contributor right now?* |
| Approver | the scope's `systemeier` | per-role `approval_type` |
| Timeout | configurable (`approval_timeout_days`) | fixed 24h, **not** configurable |

## What the demo config creates

`terraform.tfvars` covers two of the three JIT mechanisms:

| Scope | Catalog | Mechanism | Groups | What the user activates |
|---|---|---|---|---|
| `platform-demo` (Azure subscription) | `cloud-access` | `azure_pim` | `azure-platform-demo-reader`, `-contributor`, `-owner`, `-approvers` | the **role** |
| `sandbox` (AWS account) | `sandboxes` | `pim_for_groups` | `aws-sandbox-readonly`, `aws-sandbox-admin` | the **membership** |

The third, `entra_role`, is commented out. Enabling it is a tenant-wide privilege decision, not a demo step — see the notes in `terraform.tfvars`.

With `enable_access_packages = true` that becomes two catalogs and two access packages, one per scope.

## Catalogs

A catalog is a **label on a scope**, not something the vending module knows anything about:

```hcl
"sandbox" = {
  cloud   = "aws"
  catalog = "sandboxes"    # omit it and the scope lands in default_catalog
  ...
}
```

The vending module validates the label and forwards it in its contract. The packages module does `distinct()` over the labels and creates — or adopts — one catalog per label. Adding a catalog is one word in `terraform.tfvars` and no code change on either side.

Choose the boundary to match **delegation**, not environment. A catalog in Entra decides who may add resources to it and manage packages inside it. One identity team owning everything means one catalog is correct and per-scope catalogs are pure overhead. Split when a platform team should own its own packages — `delegate_to_systemeier` in the `catalogs` variable then hands them `Access package manager` on it.

## Before you apply

Replace the placeholders in `terraform.tfvars`:

- `scope_id` on `platform-demo` — a real subscription GUID
- every `@example.com` UPN — real users in your tenant

The file is valid Terraform as shipped and will pass `plan`, but `apply` fails against a real tenant until these are replaced.

## Files

```
├── main.tf             # Both module calls
├── variables.tf        # Declarations
├── versions.tf         # Providers + azurerm backend
├── outputs.tf          # Verification surface for both modules
└── terraform.tfvars    # The governance record — COMMITTED, see below
```

## Why terraform.tfvars is committed

Most Terraform templates keep tfvars out of git. This one belongs in it. For an access system the configuration **is** the governance record: "who is systemeier for prod" and "which roles require dual approval" are exactly the changes that should arrive as a reviewed pull request with history.

It holds no credentials. `tenant_id` and `provider_subscription_id` come from GitHub secrets via `TF_VAR_*`. The repo `.gitignore` has an explicit exception for this path.

## Deploying

**Actions → Deploy Identity Governance → Run workflow.** Manual dispatch only: this config decides who can become Owner on a subscription, so an accidental push to `main` must not change it.

Two choices:

| Input | Options |
|---|---|
| `action` | `plan` / `apply` / `destroy` |
| `components` | `as-configured` / `groups-and-pim` / `groups-pim-and-access-packages` |

`as-configured` follows `terraform.tfvars`, which is the honest default — a run that silently differs from the committed record is not reproducible. The explicit modes exist for staged rollout and for narrowing a run without a commit.

**Narrowing is destructive.** Selecting `groups-and-pim` when packages already exist deletes the catalogs and packages: users lose their assignments and any resource role finished by hand in the portal goes with it. The workflow refuses that `apply` unless `confirm_remove_access_packages` is set. Groups, RBAC bindings and PIM policies are never affected by the switch.

### Recommended first run on a new tenant

1. `components: groups-and-pim`, `action: apply`. Verify group names, then test activation with a hand-added member.
2. Run `scripts/verify-entitlement-management.sh` from the access-packages repo. **Eligible group membership in access packages requires Entra ID Governance or Entra Suite — P2 alone is not enough**, and a P2-only tenant fails partway through the apply rather than at plan.
3. Grant `EntitlementManagement.ReadWrite.All` to the deploy identity and get admin consent.
4. Set `enable_access_packages = true` in `terraform.tfvars`, open a PR, then `action: apply` with `components: as-configured`.

`terraform output contract` shows exactly what the packages would be built from, before you enable them.

### The deploy identity

The job runs on the self-hosted ACI runners like `demo-storage.yml`, but authenticates with **OIDC federation** rather than the runner's managed identity. Where a job runs and which identity it uses are independent choices.

By default it reuses **`AZURE_CLIENT_ID`** — the identity that deploys the runner platform. It already has `User Access Administrator` and `Contributor` on the subscription, `Storage Blob Data Contributor` on the state account, and a federated credential whose subject matches this repository. Nothing to set up on the Azure side.

**Why not the runner's managed identity:** it is attached to the container and shared by every job on the pool, so granting it `Group.ReadWrite.All` would let anything running there manage any group in the tenant. It would also need `Storage Blob Data Contributor` for the remote backend. OIDC avoids both at no extra cost.

### Graph permissions

Application permissions, admin consent required.

| Permission | Needed for |
|---|---|
| `Group.ReadWrite.All` | create and update the groups |
| `User.Read.All` | look up systemeier by UPN — `Group.ReadWrite.All` does *not* cover this, and without it every `data "azuread_user"` fails with 403 |
| `RoleManagementPolicy.ReadWrite.AzureADGroup` | the PIM activation policy, which is also what onboards a group to PIM for Groups |
| `PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup` | eligible assignments |
| `EntitlementManagement.ReadWrite.All` | **access packages only** — catalogs, packages, policies, resource roles |

The vending module's repo ships `bootstrap/grant-graph-permissions.sh` for this set — pass it the client ID. It is idempotent and skips anything already granted.

Admin consent needs a Privileged Role Administrator or Global Administrator. That is an intentional Entra boundary: it cannot be automated, because a pipeline that could grant itself tenant-wide group write would be a privilege-escalation path rather than a convenience.

> **Keep `entra_role` commented out.** It needs `RoleManagement.ReadWrite.Directory`, which lets the holder assign directory roles anywhere in the tenant including to itself. On an identity that also holds `User Access Administrator`, that combination is the one genuine problem with sharing — so while these workloads share an identity, leave it disabled.

### Splitting it out later

Set the `AZURE_VENDING_CLIENT_ID` secret and the workflow prefers it automatically, with no other change. The new principal needs the Graph set above plus `Storage Blob Data Contributor` on the state account and `User Access Administrator` on each vended subscription — **and** ownership of the groups, or `Catalog owner`, because of the `CallerNotResourceOwner` behaviour described above.

A user-assigned managed identity is the better shape, since `azurerm_user_assigned_identity` and `azurerm_federated_identity_credential` are plain ARM resources Terraform can create with the Contributor you already have. Two things to know:

- **`terraform destroy` deletes the identity, its service principal, and the Graph consent with it.** A rebuild means re-consenting and updating the secret, so give it a state file with a lifecycle separate from the demo.
- **A wrong `subject` fails silently.** The credential is created without error and only fails at token exchange, with `AADSTS700213`. Matching is case-sensitive.

Consider scoping its federated credential to a GitHub *environment* (`repo:<org>/<repo>:environment:identity-governance`) with required reviewers rather than a branch. The identity then cannot be issued to a run nobody approved.

## State

Remote state (`azurerm` backend), one key for both modules. Deliberate, not inconsistency with `storage-demo`:

- `storage-demo` is a throwaway test. Losing its state just orphans a resource group.
- This config creates **persistent** Entra groups and access packages, and runs on **ephemeral** ACI runners whose filesystem disappears with the container. With local state every run would start empty and try to recreate what already exists.

The workflow generates `backend.hcl` from the same `STATE_*` GitHub variables the runner platform uses, under its own state key (`access-vending.tfstate`). It authenticates with `use_oidc` and `use_azuread_auth` — the same federated identity as the providers, over RBAC rather than account keys.

The state account itself is **not** created here; `deploy-runners.yml` creates it on its first run.

Locally: `terraform init -backend-config=backend.hcl`.

State contains subscription IDs, group object IDs, UPNs, PIM policy content and access package configuration in plaintext. Use a storage account with RBAC, not access keys.

## Three gaps that are intentional, not forgotten

**1. `EligibleMember` cannot be set from Terraform.** `azuread_access_package_resource_package_association` validates `access_type` to `Member` and `Owner` only. The provider builds the Graph role scope as `{access_type}_{group_object_id}`, so the barrier is a client-side allowlist rather than a missing API — the Entra portal *does* offer "Eligible Member" for PIM-managed groups.

So `pim_for_groups` roles are registered as catalog resources but not attached to their package. Finishing them is one click each in the portal. `terraform output manual_steps_required` has the path. Attaching them as `Member` instead would make the user an **active** member the moment the assignment lands — standing cloud access instead of just-in-time, applying cleanly with nothing failing. That is why it takes two flags (`manage_pim_for_groups_roles` **and** `acknowledge_m3_active_membership`).

**2. `pim_for_groups` does not connect the group to the target cloud.** That is SCIM on the cloud side. `terraform output target_cloud_bindings` is the work list.

**3. `entra_role` cannot get activation rules from Terraform.** There is no policy resource for directory roles in the `azuread` provider. MFA, approval and maximum duration are set in the PIM portal, and the gap is visible in `terraform output entra_activation_governance_gap`. Note that for directory roles this means "governed by tenant admins outside Terraform" rather than "open" — active Privileged Role Administrator and Global Administrator do act as default approvers.

## Read these after an apply

A green apply says nothing about the parts Terraform cannot express.

```bash
terraform output manual_steps_required     # what to finish in the portal
terraform output excluded_resource_roles   # which groups, and what access type they need
terraform output assignment_ceilings       # per-role PIM expiry ceilings
terraform output peer_approval_status       # where a lone systemeier still deadlocks
terraform output packages_by_catalog        # delegation boundaries
```

Then run `terraform plan` again. It must report **no changes**.

## Before testing activation

The approver groups are seeded with the systemeier so a `dual` role is activatable from the first apply. But PIM blocks self-approval, so a scope with exactly one systemeier cannot activate its own `dual` role and the request times out after 24 hours — a timeout nothing can configure.

`grant_approver_group = true` (the default) grants the approver group through the access package, making everyone in the scope a peer approver. With packages disabled that fix does not exist, so add a second member to those approver groups by hand first. `terraform output peer_approval_status` reports where this matters.

## Module pinning

`main.tf` pins **both** modules to `v1.0.0`, the same tag on each. They share a versioned contract (`contract_version = 1`), so a mismatched pair fails with a type error rather than doing something subtly wrong — keeping the versions in lockstep makes the pairing obvious to a reviewer.

Both module repos must be tagged before either mode works. `count = 0` does not help: Terraform fetches every declared module regardless of `count`, and the reference to `module.access_vending.contract` has to resolve. An `init` failure mentioning a missing ref is a missing tag, not a network problem.
