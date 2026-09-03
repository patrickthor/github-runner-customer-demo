# Storage Demo — Proving the Runners Can Create Infrastructure

This example verifies that the ephemeral ACI runners provisioned by this repo can actually provision Azure infrastructure. It creates a resource group and a storage account, which is a small but complete proof of the whole platform.

## What a green run proves

Every link in the chain, in order:

1. GitHub delivered the `workflow_job` event to the Function App
2. The scaler enqueued it and created an ACI runner
3. The runner registered itself and picked up the job
4. The runner's **managed identity** had enough Azure access to run Terraform and create resources
5. The runner could reach its remote state backend

Step 4 is the reason this authenticates as the runner's managed identity (`ARM_USE_MSI`) rather than OIDC like the other two examples. That difference is deliberate. If this used a federated identity it would pass even when the runner identity was unassigned or stripped of roles, and nothing in the repo would exercise the `runner_workload_roles` the platform grants.

## Prerequisite

Run **Deploy Runners** with `apply` first. It provisions the state storage account, this example's state container, and the role assignment the runner identity needs. Without it, `init` fails with `403 AuthorizationPermissionMismatch`.

## Usage

**Actions → Demo Storage Terraform → Run workflow**, then pick `plan`, `apply`, or `destroy` — the same choice as the other two workflows.

Useful sequence:

- `apply` — creates the resource group and storage account
- `plan` again — should report **no changes**, which proves idempotency
- `destroy` — removes them

## State

Remote, in its own container on the shared state account:

| Config | Container | Key |
|---|---|---|
| `runner-demo` | `tfstate` | `runners.tfstate` |
| `access-vending-demo` | `tfstate` | `access-vending.tfstate` |
| **`storage-demo`** | `runner-jobs-tfstate` | `storage-demo.tfstate` |

The separate container is a security boundary, not tidiness. Jobs here run as the runner's managed identity, which is shared by *every* job on the pool. That identity is granted `Storage Blob Data Contributor` **scoped to this container only**, so it cannot read `access-vending.tfstate` — which contains UPNs, group object IDs, and full PIM policy content in plaintext — or the platform's own state.

Override the container name with the `RUNNER_STATE_CONTAINER` repository variable if you want a different one.

### Why not local state

It used to be local, inherited from the upstream example as a "throwaway test". On ephemeral runners that meant state never survived the job, with three consequences:

- Every `apply` leaked a resource group and storage account, with a new random name each time
- `destroy` could never remove anything — it started from empty state
- Idempotency was untestable, and a second `plan` reporting no changes is the most valuable signal Terraform gives you

## Files

```
├── main.tf             # Resource group + storage account
├── outputs.tf          # Resource names for verification
├── providers.tf        # AzureRM + Random providers
├── variables.tf        # Configurable names and location
├── versions.tf         # Provider versions + azurerm backend
└── terraform.tfvars    # Default values
```

The `random_string` suffix on the storage account originally existed to avoid collisions between runs with no state. It is kept because it is now recorded in state and stays stable — removing it would force-replace the account.
