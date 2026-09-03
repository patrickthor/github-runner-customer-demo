# Access Vending Demo — Entra Groups, RBAC and PIM

Adopts the [access-vending module](https://github.com/patrickthor/terraform-azuread-access-vending-development) and runs it on the self-hosted ACI runners provisioned by this repo.

The module vends access through Entra groups: it creates the groups, binds them to Azure RBAC or target-cloud roles, and sets the PIM activation rules. It grants **no humans access** — it defines *which* access grants exist. *Who* can receive them is decided by a sister access-package repo, which looks the groups up **by name**.

```
access-vending  (this example)          access-packages  (sister repo)
─────────────────────────────           ──────────────────────────────
WHICH access grants exist               WHO can receive them
group + role binding + PIM policy       access package per customer
                        │                        │
                        └──── group name ────────┘
                              (the contract)
```

## What the demo config creates

`terraform.tfvars` covers two of the three mechanisms:

| Scope | Mechanism | Groups | What the user activates |
|---|---|---|---|
| `platform-demo` (Azure subscription) | `azure_pim` | `azure-platform-demo-reader`, `-contributor`, `-owner`, `-approvers` | the **role** |
| `sandbox` (AWS account) | `pim_for_groups` | `aws-sandbox-readonly`, `aws-sandbox-admin` | the **membership** |

The third mechanism, `entra_role` (Entra directory roles), is left commented out. Enabling it is a tenant-wide privilege decision, not a demo step — see the notes in `terraform.tfvars`.

## Before you apply

Replace the placeholders in `terraform.tfvars`:

- `scope_id` on `platform-demo` — a real subscription GUID (currently all zeros)
- every `@example.com` UPN — real users in your tenant

The file is valid Terraform as shipped and will pass `plan`, but `apply` fails against a real tenant until these are replaced.

## Files

```
├── main.tf             # Module call (pinned to a commit SHA)
├── variables.tf        # Declarations
├── versions.tf         # Providers + azurerm backend
├── outputs.tf          # The contract the access-package repo consumes
└── terraform.tfvars    # The access configuration — COMMITTED, see below
```

## Why terraform.tfvars is committed

Most Terraform templates keep tfvars out of git. This one belongs in it. For an access-vending system the configuration **is** the governance record: "who is systemeier for prod" and "which roles require dual approval" are exactly the changes that should arrive as a reviewed pull request with history.

It holds no credentials. `tenant_id` and `provider_subscription_id` come from GitHub secrets via `TF_VAR_*`. The repo `.gitignore` has an explicit note and exception for this path.

## Deploying

**Actions → Deploy Access Vending → Run workflow**, then pick `plan`, `apply`, or `destroy`. Manual dispatch only: this config decides who can become Owner on a subscription, so an accidental push to `main` must not change it.

On `apply` the job summary prints the contract for the access-package repo — group names, access types, approver groups, system owners, and the SCIM work list.

### The vending identity

This workflow runs on the self-hosted ACI runners like `demo-storage.yml`, but authenticates with **OIDC federation** rather than the runner's managed identity. Where a job runs and which identity it uses are independent choices.

By default it reuses **`AZURE_CLIENT_ID`** — the identity that deploys the runner platform. No second identity to create.

**Why reuse it.** It already has everything except Graph: `User Access Administrator` and `Contributor` on the subscription, `Storage Blob Data Contributor` on the state account (granted by `deploy-runners.yml` when it created the account), and a federated credential whose subject already matches this repository. So there is nothing to set up on the Azure side.

**Why not the runner's managed identity,** given `demo-storage.yml` uses it: that identity is attached to the container and shared by every job on the pool, so granting it `Group.ReadWrite.All` would let anything running there manage any group in the tenant. It would also need `Storage Blob Data Contributor` added for the remote backend. OIDC avoids both at no extra cost.

### The one setup step

Grant the four Microsoft Graph application permissions to `AZURE_CLIENT_ID`:

- `Group.ReadWrite.All` — create and update the groups
- `User.Read.All` — look up systemeier by UPN (`Group.ReadWrite.All` does *not* cover this; without it every `data "azuread_user"` fails with 403)
- `RoleManagementPolicy.ReadWrite.AzureADGroup` — the PIM activation policy, which is also what onboards a group to PIM for Groups
- `PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup`

The module's repo ships `bootstrap/grant-graph-permissions.sh` for exactly this set — pass it the client ID. It is idempotent and skips anything already granted.

This needs **admin consent** from a Privileged Role Administrator or Global Administrator. That is an intentional Entra boundary: no identity choice avoids it, and it cannot be automated, because a pipeline that could grant itself tenant-wide group write would be a privilege-escalation path rather than a convenience.

> **Keep `entra_role` commented out in `terraform.tfvars`.** It needs `RoleManagement.ReadWrite.Directory`, which lets the holder assign directory roles anywhere in the tenant including to itself. On an identity that also holds `User Access Administrator`, that combination is the one genuine problem with sharing — so while these workloads share an identity, leave it disabled.

### Splitting it out later

If access vending outgrows the demo, give it its own identity: set the `AZURE_VENDING_CLIENT_ID` secret and the workflow prefers it automatically, with no other change. The new principal then needs the Graph set above plus `Storage Blob Data Contributor` on the state account and `User Access Administrator` on the subscription.

A user-assigned managed identity is the better shape for that, since `azurerm_user_assigned_identity` and `azurerm_federated_identity_credential` are plain ARM resources that Terraform can create with the Contributor you already have — no Graph permission needed to create the identity itself. Two things to know before going that way:

- **`terraform destroy` deletes the identity, its service principal, and the Graph consent with it.** A rebuild means re-consenting and updating the secret, so give it a state file with a lifecycle separate from the demo.
- **A wrong `subject` fails silently.** The credential is created without error and only fails at token exchange, with `AADSTS700213`. Matching is case-sensitive.

Consider scoping its federated credential to a GitHub *environment* (`repo:<org>/<repo>:environment:access-vending`) with required reviewers, rather than a branch. The identity then cannot be issued to a run nobody approved.

## State

Unlike `storage-demo`, this example uses **remote state** (`azurerm` backend). That is deliberate, not inconsistency:

- `storage-demo` is a throwaway test. Losing its state just orphans a resource group.
- This config creates **persistent** Entra groups that another repo references by name, and it runs on **ephemeral** ACI runners whose filesystem disappears with the container. With local state every run would start empty and try to recreate groups that already exist.

The workflow generates `backend.hcl` from the same `STATE_*` GitHub variables the runner platform uses, under a separate state key (`access-vending.tfstate`), so the two configurations never share a state file. It authenticates with `use_oidc` and `use_azuread_auth` — the same federated identity as the providers, over RBAC rather than account keys.

The state account itself is **not** created here; `deploy-runners.yml` creates it on its first run. This workflow only connects to it, which is why the vending identity needs `Storage Blob Data Contributor` granted separately.

Locally: `terraform init -backend-config=backend.hcl`.

## Two gaps that are intentional, not forgotten

1. **`pim_for_groups` does not connect the group to the target cloud.** That is done with SCIM on the cloud side. `terraform output target_cloud_bindings` is the work list.
2. **`entra_role` cannot get activation rules from Terraform.** There is no policy resource for directory roles in the `azuread` provider. MFA, approval and maximum duration are set in the PIM portal, and the gap is visible in `terraform output entra_activation_governance_gap`.

## Before testing activation

The approver groups are seeded with the systemeier so a `dual` role is activatable from the first apply. Add at least one more member before testing in earnest — an approver cannot approve their own request, so a single systemeier cannot activate their own `dual` role.

## Module pinning

`main.tf` pins the module to commit SHA `442d028`. The source repo has **no tags yet** and its only branch is `initial-setup`, so a version tag isn't available. Once a release is cut, switch the `source` ref to that tag: a SHA is immutable but tells you nothing about what changed.

The pin matters more than usual here. The access-package repo looks these groups up by name, so an unintended upgrade that changes the naming convention breaks that link — and the failure surfaces in the *other* repo as "group does not exist", not here.
