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

Copy `examples/runner-demo/` into your project (e.g., as `infra/runners/`) and copy `.github/workflows/deploy-runners.yml` to your repo's `.github/workflows/`. If you copy to a different path, update `TF_WORKING_DIR` in the workflow to match.

### 2. Create Azure identity (one-time)

Create the service principal with OIDC trust — see [Deploying identity permissions](https://github.com/patrickthor/terraform-azurerm-github-runners#deploying-identity-permissions) in the module repo for the full script.

> When creating the federated credential, set the `subject` to **your own** repository (e.g. `repo:your-org/your-repo:ref:refs/heads/main`), not the module source repo. A mismatch here is the most common cause of `AADSTS700024` failures.

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

`terraform apply` builds the infrastructure, but the platform can't serve a job yet. Three things are still missing: the credentials, the webhook, and a test.

Resource names follow `{WORKLOAD}-{ENVIRONMENT}-{INSTANCE}` from your repo variables. With `runner` / `prod` / `001` that gives Key Vault `kv-runner-prod-001`, Function App `func-runner-prod-001`, resource group `rg-runner-prod-001`. Set them once:

```bash
KV=kv-runner-prod-001
RG=rg-runner-prod-001
FUNC=func-runner-prod-001
```

### 1. Store the GitHub App secrets in Key Vault

The module creates the Key Vault and grants the Function App read access, but it does not populate the values — you do that here, once.

You need three things from your GitHub App:

| Value | Where to get it |
|---|---|
| App ID | The App's settings page |
| Installation ID | `gh api /repos/<org>/<repo>/installation --jq .id` |
| Private key PEM | Generate on the App's settings page (downloads a `.pem`) |

The vault uses RBAC, so grant yourself data-plane access first — without this every `secret set` fails with `Forbidden`:

```bash
az role assignment create \
  --assignee "$(az ad signed-in-user show --query id -o tsv)" \
  --role "Key Vault Secrets Officer" \
  --scope "$(az keyvault show --name $KV --query id -o tsv)"
```

Allow up to a minute for the assignment to propagate, then store the secrets. The names must match the `*_secret_name` values passed to the module — the defaults are below:

```bash
az keyvault secret set --vault-name $KV --name github-app-id \
  --value "<APP_ID>" -o none

az keyvault secret set --vault-name $KV --name github-app-installation-id \
  --value "<INSTALLATION_ID>" -o none

az keyvault secret set --vault-name $KV --name github-app-private-key \
  --file <path/to/private-key.pem> -o none
```

> `-o none` matters. Without it the CLI echoes the secret back, putting your private key in the terminal scrollback and in any CI log.

Verify all three landed, without printing the key:

```bash
az keyvault secret list --vault-name $KV --query "[].name" -o tsv
```

Then **delete the local `.pem`**. It is a signing key for the App — anything holding it can mint runner registration tokens for your repo. Nothing in this repo ignores `*.pem`, so an accidental `git add` would commit it.

### 2. Register the webhook

Get the hostname and function key. These read from Azure directly, so they work without local Terraform state:

```bash
az functionapp show --resource-group $RG --name $FUNC \
  --query defaultHostName -o tsv

az functionapp function keys list --resource-group $RG --name $FUNC \
  --function-name github_webhook --query default -o tsv
```

In the repository that will run the jobs: **Settings → Webhooks → Add webhook**

| Field | Value |
|---|---|
| Payload URL | `https://<hostname>/api/webhook/github?code=<function_key>` |
| Content type | `application/json` |
| Events | *Let me select individual events* → **Workflow jobs** only |
| Secret | Leave empty — see the note below |

> **Signature validation is off in this example.** `examples/runner-demo/main.tf` does not set `webhook_secret_secret_name`, and the scaler skips verification entirely when that setting is absent — returning `200` to unsigned payloads. Anyone who learns the URL and function key can inject fake `workflow_job` events and spawn runners. To enable it: set `webhook_secret_secret_name = "github-webhook-secret"` on the module call, re-run the deploy, store that secret in the vault, and put the same value in the **Secret** field above.

### 3. Verify it works

**Actions → Demo Storage Terraform → Run workflow.** It targets `runs-on: [self-hosted, azure, container-instance]`, so a green run proves the whole chain: GitHub delivered the event, the Function App accepted it, the scaler minted a registration token from the Key Vault credentials, ACI pulled the image from ACR, and the runner registered and picked up the job.

If the job stays queued, work through it in this order:

| Check | What it tells you |
|---|---|
| **Settings → Webhooks → Recent Deliveries** | A non-`2xx` means the request never reached the scaler — usually a wrong function key, or your caller IP is outside the allowed GitHub ranges |
| `200` but no container appears in the resource group | Labels don't match `runner_labels`, or `runner_max_instances` is already reached |
| Container starts then dies immediately | Key Vault secrets missing or wrong, or the App isn't installed on *this* repository |
| Application Insights traces on `func-...` | The scaler's own errors. Service Bus is Basic tier with no dead-letter queue, so this is the only debugging surface |

## Troubleshooting

**Scaler errors straight after the first deploy.** The Function App starts during `terraform apply`, before you've stored the Key Vault secrets in [step 1 above](#1-store-the-github-app-secrets-in-key-vault). It logs authentication errors on every webhook delivery until they exist. That's expected, not a failure — store the secrets and the next event succeeds. Nothing needs restarting.

**GitHub App installation scope.** The App must be installed on the specific repository that sends the webhook events. An org-level App still needs installing on the target repo via its "Install" page.

**`AADSTS700024` in the deploy workflow.** The federated credential `subject` doesn't match the repo and branch actually running the workflow. It must be exact — `repo:<org>/<repo>:ref:refs/heads/main`.

**Module version.** `examples/runner-demo/main.tf` currently pins `?ref=main`, which is not a stable interface — the module repo can change it under you. Pin a release tag instead (`v3.0.8` is current). Note the `RUNNER_MODULE_REF` variable above only controls which tag the *scaler function code* is fetched from; the Terraform module version is the `source` line in `main.tf`, and the two should agree.
