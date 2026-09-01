# Basic Example — Consuming the Runners Module

This example shows the minimum setup needed to deploy the GitHub runners platform in your own project. All configuration is driven by GitHub repository secrets and variables — no hardcoded values in the Terraform files.

## Files

```
├── examples/
│   ├── runner-demo/                         # Runner platform module usage
│   │   ├── main.tf                          # Module call (reads from variables)
│   │   ├── variables.tf                     # Variable declarations
│   │   └── versions.tf                      # Provider and backend configuration
│   ├── storage-demo/                        # Self-hosted runner test (storage account)
│   └── access-vending-demo/                 # Entra groups + RBAC + PIM via access-vending module
└── .github/workflows/
    ├── deploy-runners.yml                   # Runner platform (generates tfvars from GitHub variables)
    ├── demo-storage.yml                     # storage-demo, on self-hosted runners
    └── deploy-access-vending.yml            # access-vending-demo, on self-hosted runners
```

## Examples

| Example | Workflow | Runs on | What it does |
|---|---|---|---|
| `runner-demo` | `deploy-runners.yml` | `ubuntu-latest` (OIDC) | Deploys the runner platform itself |
| `storage-demo` | `demo-storage.yml` | self-hosted ACI | Smoke test — proves runners have working Azure creds |
| `access-vending-demo` | `deploy-access-vending.yml` | self-hosted ACI | Vends access via Entra groups, RBAC bindings and PIM policies |

> `access-vending-demo` needs extra Graph and RBAC permissions on the runner identity before its first run — see [its README](examples/access-vending-demo/README.md#permissions-the-runner-identity-needs).

## Quick start

### 1. Copy files into your project

Copy `examples/runner-demo/` into your project (e.g., as `infra/runners/`) and copy `.github/workflows/deploy-runners.yml` to your repo's `.github/workflows/`. If you copy to a different path, update `TF_WORKING_DIR` and the `push` path filters in the workflow accordingly.

### 2. Create Azure identity (one-time)

Follow [step 2 in the main README](../../README.md#2-provision-azure-identity-and-permissions) to create the service principal with OIDC trust.

> When creating the federated credential, set the `subject` to your own repository (e.g. `repo:your-org/your-repo:ref:refs/heads/main`), not the module source repo.

### 3. Configure GitHub secrets and variables

**Secrets** (Settings → Secrets and variables → Actions → Repository secrets):

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | Service principal client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |

**Variables** (Settings → Secrets and variables → Actions → Repository variables):

| Variable | Example | Description |
|---|---|---|
| `WORKLOAD` | `runner` | Short workload identifier |
| `ENVIRONMENT` | `prod` | Environment (e.g. prod, dev) |
| `INSTANCE` | `001` | Instance for uniqueness |
| `AZURE_LOCATION` | `westeurope` | Azure region |
| `GH_ORG` | `your-org` | GitHub organization |
| `GH_REPO` | `your-org/your-repo` | Repository in org/repo format |
| `RUNNER_MODULE_REF` | `v3.0.0` | Module version tag (optional, defaults to v3.0.0) |
| `RUNNER_WORKLOAD_ROLES` | `Contributor` | Comma-separated Azure roles for runner identity (optional) |
| `STATE_RESOURCE_GROUP` | `rg-tfstate` | Resource group for state storage (created automatically if missing) |
| `STATE_STORAGE_ACCOUNT` | `sttfstate1a2b` | Storage account name for Terraform state (created automatically if missing) |
| `STATE_CONTAINER` | `tfstate` | Blob container name (optional, defaults to tfstate) |

### 4. Run the deploy workflow

**Actions → Deploy Runners → Run workflow.** All workflows in this repo are
manual dispatch only — they apply Terraform against a live subscription, so
nothing deploys on a push to `main`.

The workflow is fully self-service. On the first run it will:
- Create the state storage account and blob container (if they don't exist)
- Grant the CI identity `Storage Blob Data Contributor` on the storage account
- Generate `terraform.tfvars` and `backend.hcl` from your GitHub variables
- Run `terraform apply` (infrastructure)
- Import the runner container image into ACR
- Deploy the scaler function code (fetched from the module repo)

Subsequent runs skip the storage creation and just connect to the existing state.

## After first deploy

1. Store GitHub App secrets in the Key Vault — see [main README step 6](../../README.md#6-store-github-app-secrets-in-key-vault)
2. Register the GitHub webhook — see [main README step 7](../../README.md#7-register-the-webhook-in-github)
3. Trigger a workflow with `runs-on: [self-hosted, azure, container-instance]` to test

## Troubleshooting

**Key Vault secrets timing**: The Function App starts immediately after `terraform apply`, but Key Vault secrets (step 6) aren't stored yet. The scaler will log errors until the secrets exist — this is expected. Store the secrets, then the next webhook event will work.

**GitHub App installation scope**: The App must be installed on the specific repository that sends webhook events. If you created an org-level App, install it on the target repo via the App's "Install" page.

**OIDC federated credential subject mismatch**: The `subject` in the federated credential must exactly match your repo and branch. A `repo:wrong-org/wrong-repo:ref:refs/heads/main` subject will cause `AADSTS700024` errors in the workflow.
