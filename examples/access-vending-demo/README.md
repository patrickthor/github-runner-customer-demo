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

### Permissions the runner identity needs

This is the part that will block a first run. The workflow authenticates as the ACI runner's managed identity, which the runner module creates with least privilege. It needs:

**Microsoft Graph** (application permissions, admin consent required):
- `Group.ReadWrite.All`
- `User.Read.All`
- `RoleManagementPolicy.ReadWrite.AzureADGroup`
- `PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup`

**Azure RBAC:**
- `User Access Administrator` on each vended subscription (only for `azure_pim` roles). `Role Based Access Control Administrator` is *not* enough — it covers role bindings but not PIM policies.
- `Storage Blob Data Contributor` on the Terraform state storage account.

The module's own repo ships `bootstrap/grant-graph-permissions.sh`, which grants exactly the Graph set above.

> **Security trade-off, stated plainly:** granting `Group.ReadWrite.All` to the *shared* runner identity means every workflow on these runners can manage every group in the tenant. Defensible for a demo; not for anything real. For production, run this on `ubuntu-latest` with a dedicated OIDC service principal — there's a commented block in the workflow showing how.

## State

Unlike `storage-demo`, this example uses **remote state** (`azurerm` backend). That is deliberate, not inconsistency:

- `storage-demo` is a throwaway test. Losing its state just orphans a resource group.
- This config creates **persistent** Entra groups that another repo references by name, and it runs on **ephemeral** ACI runners whose filesystem disappears with the container. With local state every run would start empty and try to recreate groups that already exist.

The workflow generates `backend.hcl` from the same `STATE_*` GitHub variables the runner platform uses, under a separate state key (`access-vending.tfstate`), so the two configurations never share a state file.

Locally: `terraform init -backend-config=backend.hcl`.

## Two gaps that are intentional, not forgotten

1. **`pim_for_groups` does not connect the group to the target cloud.** That is done with SCIM on the cloud side. `terraform output target_cloud_bindings` is the work list.
2. **`entra_role` cannot get activation rules from Terraform.** There is no policy resource for directory roles in the `azuread` provider. MFA, approval and maximum duration are set in the PIM portal, and the gap is visible in `terraform output entra_activation_governance_gap`.

## Before testing activation

The approver groups are seeded with the systemeier so a `dual` role is activatable from the first apply. Add at least one more member before testing in earnest — an approver cannot approve their own request, so a single systemeier cannot activate their own `dual` role.

## Module pinning

`main.tf` pins the module to commit SHA `442d028`. The source repo has **no tags yet** and its only branch is `initial-setup`, so a version tag isn't available. Once a release is cut, switch the `source` ref to that tag: a SHA is immutable but tells you nothing about what changed.

The pin matters more than usual here. The access-package repo looks these groups up by name, so an unintended upgrade that changes the naming convention breaks that link — and the failure surfaces in the *other* repo as "group does not exist", not here.
