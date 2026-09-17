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
| `sandbox` (AWS account) | `sandboxes` | `pim_for_groups` | `aws-sandbox-readonly`, `aws-sandbox-admin`, `-approvers` | the **membership** |

`sandbox-admin` uses `approval_type = "dual"`, which is what makes the vending module create `aws-sandbox-approvers`. Under contract v2 that group is granted by its own **approver package**, not bolted onto the access package — and the sandbox access package grants real membership, because each `pim_for_groups` role now has a plain eligibility-carrier group the package can attach as `Member`. See [gap 1](#two-gaps-that-are-intentional-not-forgotten).

The third, `entra_role`, is commented out. Enabling it is a tenant-wide privilege decision, not a demo step — see the notes in `terraform.tfvars`.

Under `components: groups-pim-and-access-packages` that gains two catalogs (`cloud-access`, `sandboxes`) and two access packages, one per scope.

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

## Access reviews

Two models side by side, deliberately:

| Package | Assignment | Recurring control |
|---|---|---|
| `platform-engineers` | 180 days | **quarterly review** by the systemeier |
| `platform-admins` | 60 days | **monthly review** by the systemeier |
| `sandbox` | 10 days | **expiry** — no review |
| approver packages (both) | 180 days | **quarterly review** |

Reviews and short expiry are *alternatives*, not complements. A review on a 7-day assignment sees an empty subject list, because the assignment lapses long before the first campaign runs. The module enforces this: a reviewed package must have `assignment_duration_days` **longer** than its review interval (weekly 7, monthly 30, quarterly 90, halfyearly 180, annual 365).

That is why the reviewed packages have longer durations than before. It *is* a loosening, and the review is what pays for it — Contributor and Owner still require PIM activation with dual approval and MFA every single time.

**`sandbox` has no review, and cannot have one as configured.** `sandbox-admin` sets `active_assignment_expire_after = "P15D"`, which caps the assignment at 15 days, so every interval except weekly outlives what the assignment can live. The module rejects that and points at the vending config, because the fix is to raise `active_assignment_expire_after` in `access_scopes` — trading a longer standing eligibility window for a review someone has to action. Left as-is so the demo shows both models.

All reviews use `removeAccess` on timeout: no response means access ends. That is what separates a review from an attestation exercise. `review_type` is `Reviewers` (the scope's systemeier) — **not** `Manager`, which the module rejects because B2B guests have no manager attribute and the campaign would fall silently through to the timeout.

No extra Graph permission: a review is a field on the assignment policy, covered by `EntitlementManagement.ReadWrite.All`.

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

Three choices.

**`action`** — `plan`, `apply` or `destroy`.

**`components`** — what to deploy:

| | Creates | Gate | Extra requirements |
|---|---|---|---|
| `groups-and-pim` (default) | Entra groups, Azure RBAC bindings, PIM activation policies | gate 2 | none beyond the group + PIM Graph permissions |
| `groups-pim-and-access-packages` | the above, plus catalogs, access packages and assignment policies | gates 1 and 2 | `EntitlementManagement.ReadWrite.All`, and Entra ID Governance or Entra Suite licensing |

With `groups-and-pim` nothing is requestable: no user can obtain access without being added to a group by hand. It needs no entitlement-management licensing, which is why it is the default and the mode to run first.

The choice sets `TF_VAR_enable_access_packages`, which gates `module "access_packages"`. It is **not** in `terraform.tfvars` — a `TF_VAR` always beats a tfvars entry, so a copy there could never take effect. The switch has exactly one home.

**`deploy_access_reviews`** — a checkbox, off by default. Adds a recurring access review to the packages that have an `access_reviews` block in `terraform.tfvars`. Requires access packages; the workflow rejects the combination with `groups-and-pim` before planning, since a review attaches to an assignment policy.

The split is the same as `components`: **the pipeline decides whether, `terraform.tfvars` decides what.** A `TF_VAR` always beats a tfvars entry, so the on/off switch has exactly one home. With the box unticked, review configuration is still resolved and reported as `deployed = false` — see `terraform output access_reviews_configured_not_deployed`, which is the state most easily misread as "reviews are on".

Unticking it after reviews exist removes them. That is only a **warning**, not a block, because `azuread_access_package_assignment_policy` declares `ForceNew` on nothing: removing the review block is an in-place update, no assignment is dropped and nobody loses access. What is lost is the review campaign and its history.

**Switching back down is destructive.** Selecting `groups-and-pim` after packages exist deletes the catalogs and packages: users lose their assignments, and any resource role finished by hand in the portal goes with it. The workflow reads that out of the plan and refuses the `apply` unless `confirm_remove_access_packages` is set. Groups, RBAC bindings and PIM policies are never affected by the switch.

### Recommended first run on a new tenant

1. `action: plan`, `components: groups-and-pim`. Exercises `init`, the module pins, the contract assembly and both providers without writing anything.
2. `action: apply`, same components. Verify the group names, then test activation with a hand-added member.
3. Run `scripts/verify-entitlement-management.sh` from the access-packages repo. **Eligible group membership in access packages requires Entra ID Governance or Entra Suite — P2 alone is not enough**, and a P2-only tenant fails partway through the apply rather than at plan.
4. Grant `EntitlementManagement.ReadWrite.All` to the deploy identity and get admin consent.
5. `action: plan`, `components: groups-pim-and-access-packages`. Then `apply`.

Between steps 2 and 5, `terraform output contract` shows exactly what the packages will be built from.

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

## Two gaps that are intentional, not forgotten

**1. `pim_for_groups` does not connect the group to the target cloud.** That is SCIM on the cloud side. `terraform output target_cloud_bindings` is the work list. Note that the eligibility-carrier groups deliberately do **not** appear there — they must never be provisioned anywhere, or their members would hold standing access and PIM would be bypassed.

**2. `entra_role` cannot get activation rules from Terraform.** There is no policy resource for directory roles in the `azuread` provider. MFA, approval and maximum duration are set in the PIM portal, and the gap is visible in `terraform output entra_activation_governance_gap`. Note that for directory roles this means "governed by tenant admins outside Terraform" rather than "open" — active Privileged Role Administrator and Global Administrator do act as default approvers.

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

Approver rights are their own access package now, created by default for every scope that has an approver group. Requesting it makes you a peer approver without granting you the access itself, so a second person can be added without handing them Owner. With access packages disabled that route does not exist, so add a second member to the approver group by hand first. `terraform output peer_approval_status` reports where this matters, and `terraform output approver_packages` shows the packages.

## Module pinning

`main.tf` pins both modules to a **commit SHA**, because neither module repo has tags yet:

| Module | Ref | Commit |
|---|---|---|
| `access-vending` | `008f72c8fd92f8f168cc8ba8d21337931cf72066` | `initial-setup` @ 2026-09-04, "reowkr the whole thing" |
| `access-packages` | `5a046e5ca0c8353039656ef62387ef7305fc46f5` | `inital-commit` @ 2026-09-04, "Major rework" |

Immutability is the property that matters, but a SHA tells you nothing about what changed — so **switch both pins to `v1.0.0` once the tags are cut**, and keep them in lockstep. The modules share a versioned contract (`contract_version = 1`), so a mismatched pair fails with a type error rather than doing something subtly wrong.

A branch ref would be wrong here even though both branches exist: these groups are the resource identity the access packages attach to, so an unintended module change can orphan every package association — and the failure surfaces on the package side, not the group side.

`count = 0` does not exempt the second module from this. Terraform fetches every declared module regardless of `count`, and the reference to `module.access_vending.contract` has to resolve. So an `init` failure naming a missing ref is a bad pin, not a network problem, in either mode.
