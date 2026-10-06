# GitHub Runners and Identity Governance Demo

This repository demonstrates the GitHub runners platform, a two-module Entra identity-governance chain, and provider-side generation of customer-specific Azure Lighthouse ARM artifacts.

## Files

```
├── examples/
│   ├── runner-demo/                         # Runner platform module usage
│   ├── storage-demo/                        # Self-hosted runner test
│   ├── access-vending-demo/                 # Entra groups + PIM + access packages
│   └── lighthouse-arm-demo/                 # Parameter-free Lighthouse ARM rendering
├── runner-image/                            # Pinned self-hosted image + Azure CLI
├── docs/steering/                           # Module implementation guidance
└── .github/workflows/
    ├── deploy-runners.yml                   # Runner platform
    ├── demo-storage.yml                     # Self-hosted storage test
    ├── deploy-access-vending.yml            # Identity governance
    └── publish-lighthouse-arm.yml            # Immutable Lighthouse ARM artifacts
```

## Examples

| Example | Workflow | Runs on | Auth | What it does |
|---|---|---|---|---|
| `runner-demo` | `deploy-runners.yml` | `ubuntu-latest` | OIDC | Deploys the runner platform itself |
| `storage-demo` | `demo-storage.yml` | self-hosted ACI | runner MI | Proves the runners can create infrastructure |
| `access-vending-demo` | `deploy-access-vending.yml` | self-hosted ACI | OIDC | Entra groups, RBAC/PIM, and optional access packages/reviews |
| `lighthouse-arm-demo` | `publish-lighthouse-arm.yml` | self-hosted ACI | OIDC | Renders and immutably publishes parameter-free Lighthouse ARM JSON |

The Lighthouse publisher is intentionally separate from the access-vending state. It accepts customer-specific managing-tenant principal UUIDs once in its committed `terraform.tfvars`, fixes the Lighthouse module to ARM mode, and uploads versioned JSON to a private Blob container. It never authenticates to or changes a customer subscription. Terraform-capable customers consume the same [Lighthouse module](https://github.com/patrickthor/JSONARM-lighthouse-manifesto) in native `terraform` mode from their own customer-side repository and state. One delegation must use only one ownership path.

`access-vending-demo` calls **two** modules against **one** state, so its workflow takes a second choice — `components` — for what to deploy:

| `components` | Deploys | Needs |
|---|---|---|
| `groups-and-pim` (default) | Entra groups, RBAC bindings, PIM policies — **gate 2** | Graph group + PIM permissions |
| `groups-pim-and-access-packages` | the above, plus catalogs and access packages — **gate 1** | also `EntitlementManagement.ReadWrite.All`, and Entra ID Governance or Entra Suite licensing |

With `groups-and-pim` nothing is requestable, so no user can obtain access without being added to a group by hand. That is the mode to run first on a new tenant.

Selecting `groups-and-pim` after packages exist **deletes** the catalogs and packages, so an `apply` in that direction needs `confirm_remove_access_packages`. Groups, RBAC and PIM policies are never touched by the switch.

A third input, **`deploy_access_reviews`**, is a checkbox rather than a dropdown value — recurring reviews are orthogonal to *what* gets deployed. It requires access packages, and the workflow rejects the invalid combination before planning.

`storage-demo` authenticates as the runner's managed identity rather than OIDC on purpose — it exists to prove what *the runner* can do, so using a federated identity would pass even with the runner identity broken.

**Order matters:** run `deploy-runners.yml` with `apply` first. It creates the shared storage account and state containers. The Lighthouse publishing workflow creates its own private artifact container on first publish; it refuses to reuse either Terraform-state container.

> `access-vending-demo` and the Lighthouse publisher prefer the optional dedicated OIDC identity in `AZURE_VENDING_CLIENT_ID`, and otherwise reuse `AZURE_CLIENT_ID`. The selected identity needs the permissions documented by each example.

## Quick start

### 1. Copy files into your project

Copy `examples/runner-demo/` into your project (e.g., as `infra/runners/`) and copy `.github/workflows/deploy-runners.yml` to your repo's `.github/workflows/`. If you copy to a different path, update `TF_WORKING_DIR` in the workflow to match.

### 2. Create the Azure OIDC deployment identity

The first group of three GitHub Actions secrets identifies an Azure service principal. They are IDs, not passwords; OIDC lets GitHub request a short-lived Azure token, so there is deliberately no `AZURE_CLIENT_SECRET`.

If you already have the deployment identity, find the values in Azure Portal:

| GitHub secret | Azure Portal location | Azure CLI |
|---|---|---|
| `AZURE_CLIENT_ID` | **Microsoft Entra ID → App registrations → your app → Application (client) ID** | `az ad app list --display-name <app-name> --query '[0].appId' -o tsv` |
| `AZURE_TENANT_ID` | **Microsoft Entra ID → Overview → Tenant ID** | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | **Subscriptions → target subscription → Subscription ID** | `az account show --query id -o tsv` |

To create a new identity, sign in as someone allowed to create app registrations and assign roles on the target subscription, then run the following after replacing the first four values:

```bash
APP_NAME="sp-github-runner-demo"
GITHUB_OWNER="your-org"
GITHUB_REPO="your-repo"       # repository name only
GITHUB_BRANCH="main"
SUBSCRIPTION_ID="<target-subscription-id>"

az account set --subscription "$SUBSCRIPTION_ID"
TENANT_ID=$(az account show --query tenantId -o tsv)

# Create the Entra application and its service-principal instance.
CLIENT_ID=$(az ad app create \
  --display-name "$APP_NAME" \
  --query appId -o tsv)
SP_OBJECT_ID=$(az ad sp create --id "$CLIENT_ID" --query id -o tsv)

APP_OBJECT_ID=$(az ad app show --id "$CLIENT_ID" --query id -o tsv)

# Trust only workflow tokens issued for this repository and branch.
az ad app federated-credential create \
  --id "$APP_OBJECT_ID" \
  --parameters "{
    \"name\": \"github-actions-${GITHUB_BRANCH}\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_OWNER}/${GITHUB_REPO}:ref:refs/heads/${GITHUB_BRANCH}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" -o none

SUBSCRIPTION_SCOPE="/subscriptions/$SUBSCRIPTION_ID"

# The module creates Azure resources and role assignments for its identities.
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role Contributor \
  --scope "$SUBSCRIPTION_SCOPE" -o none

az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" \
  --scope "$SUBSCRIPTION_SCOPE" -o none

printf 'AZURE_CLIENT_ID=%s\nAZURE_TENANT_ID=%s\nAZURE_SUBSCRIPTION_ID=%s\n' \
  "$CLIENT_ID" "$TENANT_ID" "$SUBSCRIPTION_ID"
```

These subscription-wide grants are convenient for this demo and broader than a production deployment should normally receive. The federated credential subject must match the repository owner, repository name, and branch exactly.

Add the printed values under **GitHub repository → Settings → Secrets and variables → Actions → Secrets → New repository secret**. Alternatively, while authenticated to the target GitHub repository with `gh`:

```bash
gh secret set AZURE_CLIENT_ID --body "$CLIENT_ID"
gh secret set AZURE_TENANT_ID --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID"
```

See Microsoft’s [OIDC setup guidance](https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect#prerequisites) for the underlying trust model.

### 3. Configure GitHub repository variables

Open **Settings → Secrets and variables → Actions → Variables** and add:

| Variable | Example | Description |
|---|---|---|
| `WORKLOAD` | `runner` | Short workload identifier |
| `ENVIRONMENT` | `prod` | Environment (e.g. prod, dev) |
| `INSTANCE` | `001` | Instance for uniqueness |
| `AZURE_LOCATION` | `westeurope` | Azure region |
| `GH_ORG` | `your-org` | GitHub organization |
| `GH_REPO` | `your-org/your-repo` | Repository in org/repo format |
| `RUNNER_WORKLOAD_ROLES` | `Contributor` | Comma-separated Azure roles for runner identity (optional) |
| `STATE_RESOURCE_GROUP` | `rg-tfstate` | Resource group for state storage (created automatically if missing) |
| `STATE_STORAGE_ACCOUNT` | `sttfstate1a2b` | Storage account name for Terraform state (created automatically if missing) |
| `STATE_CONTAINER` | `tfstate` | Blob container for the platform and access-vending state (optional, defaults to tfstate) |
| `RUNNER_STATE_CONTAINER` | `runner-jobs-tfstate` | Blob container for state written *by jobs on the runners* (optional). Kept separate so the shared runner identity cannot read the other state files |
| `LIGHTHOUSE_ARTIFACT_CONTAINER` | `lighthouse-artifacts` | Private container for immutable customer ARM JSON (optional). Must differ from both state containers |

### 4. Run the deploy workflow

**Actions → Deploy Runners → Run workflow.** All workflows in this repo are
manual dispatch only — they apply Terraform against a live subscription, so
nothing deploys on a push to `main`.

The workflow is fully self-service. On the first run it will:
- Create the state storage account and blob container (if they don't exist)
- Grant the CI identity `Storage Blob Data Contributor` on the storage account
- Generate `terraform.tfvars` and `backend.hcl` from your GitHub variables
- Run `terraform apply` (infrastructure)
- Build the repository-owned runner image in ACR from `runner-image/Dockerfile`
- Deploy the scaler function code (fetched from the module repo)

The runner Dockerfile pins the upstream Linux/amd64 image digest and adds a pinned Azure CLI package from Microsoft’s signed apt repository. This keeps Azure workloads on the ephemeral self-hosted ACI runners without downloading privileged tooling during each job. After changing the Dockerfile or rebuilding the runner platform, run `deploy-runners.yml` with `apply` before starting workflows that require `az`.

Subsequent runs skip the storage creation and just connect to the existing state.

## After first deploy

`terraform apply` builds the infrastructure, but the platform can't serve a job yet. Three things are still missing: the credentials, the webhook, and a test.

Resource names follow `{WORKLOAD}-{ENVIRONMENT}-{INSTANCE}` from your repo variables. With `runner` / `prod` / `001` that gives Key Vault `kv-runner-prod-001`, Function App `func-runner-prod-001`, resource group `rg-runner-prod-001`. Set them once:

```bash
KV=kv-runner-prod-001
RG=rg-runner-prod-001
FUNC=func-runner-prod-001
```

### 1. Create and install the GitHub App, then store its credentials

This is a second, separate identity from the Azure OIDC service principal above. The Azure identity deploys infrastructure; the GitHub App lets the scaler request short-lived runner registration tokens and inspect queued workflow jobs. The module creates the Key Vault and grants the Function App read access, but you must create the GitHub App and populate these three Key Vault secrets after the first apply.

#### Create the GitHub App

Create it under the account that owns the target repository:

- Personal account: [github.com/settings/apps/new](https://github.com/settings/apps/new)
- Organization: `https://github.com/organizations/<your-org>/settings/apps/new`

Configure:

| Setting | Value |
|---|---|
| GitHub App name | A globally unique name such as `runner-demo-your-org` |
| Homepage URL | This repository URL, or your organization homepage |
| Webhook | Clear **Active**; this solution registers a separate repository webhook later |
| Repository permission: **Administration** | **Read and write** — required to mint repository runner registration tokens |
| Repository permission: **Actions** | **Read-only** — used to inspect workflow-job state |
| Where can this GitHub App be installed? | **Only on this account** for the demo |

Leave unrelated permissions at **No access**, then select **Create GitHub App**. GitHub’s current UI steps are documented in [Creating a GitHub App](https://docs.github.com/en/apps/creating-github-apps/setting-up-a-github-app/creating-a-github-app).

#### Install it on the repository

From the new App’s settings page, select **Install App → Install** next to the owning account. Choose **Only select repositories**, select this repository, and complete the installation. Creating the App is not enough: it must be installed on the exact repository whose workflow jobs will trigger runners. See [Installing your own GitHub App](https://docs.github.com/en/apps/using-github-apps/installing-your-own-github-app).

#### Collect the three values

| Key Vault secret | How to obtain the value |
|---|---|
| `github-app-id` | On the App settings page, copy the numeric **App ID**. Do not use the **Client ID**, and do not use Azure’s application ID. |
| `github-app-installation-id` | After installation, run `gh api /repos/<owner>/<repo>/installation --jq .id`. This is the installation instance ID, not the App ID. |
| `github-app-private-key` | On the App settings page under **Private keys**, select **Generate a private key**. GitHub downloads the only copy of the private key as a `.pem` file; see [Managing private keys for GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps). |

Only the PEM is cryptographic secret material. The App ID and installation ID are identifiers, but this implementation stores all three in Key Vault so the Function App reads them through one controlled channel.

Set local variables so the commands below are unambiguous:

```bash
GH_OWNER="your-org"
GH_REPO="your-repo"
APP_ID="<numeric-app-id-from-the-app-settings-page>"
PEM_FILE="$HOME/Downloads/<downloaded-private-key>.pem"

# gh must be authenticated as a user allowed to see the installation.
gh auth status
INSTALLATION_ID=$(gh api "/repos/$GH_OWNER/$GH_REPO/installation" --jq .id)

printf 'App ID: %s\nInstallation ID: %s\nPrivate key: %s\n' \
  "$APP_ID" "$INSTALLATION_ID" "$PEM_FILE"
```

If the installation lookup returns `404`, the App is not installed on that repository or the user authenticated by `gh` cannot see the installation. GitHub documents the installation-ID endpoint in [Generating an installation access token](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app#get-the-id-of-the-installation-that-you-want-to-authenticate-as).

#### Store the values in Azure Key Vault

The vault uses RBAC, so grant yourself data-plane access first — without this every `secret set` fails with `Forbidden`:

```bash
az role assignment create \
  --assignee "$(az ad signed-in-user show --query id -o tsv)" \
  --role "Key Vault Secrets Officer" \
  --scope "$(az keyvault show --name $KV --query id -o tsv)"
```

Allow up to a minute for the assignment to propagate, then store the secrets. The names must match the `*_secret_name` values passed to the module — the defaults are below:

```bash
az keyvault secret set --vault-name "$KV" --name github-app-id \
  --value "$APP_ID" -o none

az keyvault secret set --vault-name "$KV" --name github-app-installation-id \
  --value "$INSTALLATION_ID" -o none

az keyvault secret set --vault-name "$KV" --name github-app-private-key \
  --file "$PEM_FILE" -o none
```

> `-o none` matters. Without it the CLI echoes the secret back, putting your private key in the terminal scrollback and in any CI log.

Verify all three landed, without printing the key:

```bash
az keyvault secret list --vault-name $KV --query "[].name" -o tsv
```

Then **delete the local `.pem` securely** after confirming the Key Vault secret exists. It is a signing key for the App—anything holding it can mint installation tokens with the App’s permissions. This repository now ignores `*.pem`, but the file should still not remain on a workstation longer than necessary.

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

**Scaler errors straight after the first deploy.** The Function App starts during `terraform apply`, before you've stored the Key Vault secrets in [step 1 above](#1-create-and-install-the-github-app-then-store-its-credentials). It logs authentication errors on every webhook delivery until they exist. That's expected, not a failure — store the secrets and the next event succeeds. Nothing needs restarting.

**GitHub App installation scope.** The App must be installed on the specific repository that sends the webhook events. An org-level App still needs installing on the target repo via its "Install" page.

**`AADSTS700024` in the deploy workflow.** The federated credential `subject` doesn't match the repo and branch actually running the workflow. It must be exact — `repo:<org>/<repo>:ref:refs/heads/main`.

**Runner source version.** Terraform infrastructure and scaler Function code are both pinned to immutable commit `916e8d08874cc1df596a5fd391228d56cba865f1`. The workflow verifies that its `MODULE_REF` matches the `?ref=` in `examples/runner-demo/main.tf` before Azure login. There is no repository-variable override because that could silently deploy infrastructure and code from different revisions. Replace both pins with the same release tag when the runner module publishes a release that raises its AzureRM floor to 5.6.0 or newer.

**Service Bus namespace stuck in `Failed`.** The runner root uses AzureRM `~> 5.7.0`; AzureRM 5.6.0 moved Service Bus to control-plane API `2026-01-01`. Keep the module's Basic SKU, TLS 1.2, and disabled local authentication. Do not add `zone_redundant` or change to Premium: Azure automatically enables zone redundancy for every tier in supported regions. The provider upgrade prevents the known 5.4.x API boundary from being reused, but only a clean namespace deployment can confirm the diagnosis. A namespace already in `Failed` with `CreateNamespacePayloadDiffersFromExistingNamespaceInFailedState` must be explicitly deleted after approval and shown absent before applying again; retries cannot repair it.
