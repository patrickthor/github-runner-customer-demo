# Demo — Self-Hosted Runner Workflow

This example is an internal test that runs on the self-hosted runners provisioned by this module. It creates a simple resource group and storage account to verify that the runners have working Azure credentials and can execute Terraform.

## How it works

The `demo-storage.yml` workflow runs on `self-hosted, azure, container-instance` labels, which routes it to the ACI runners. The runner authenticates to Azure using its user-assigned managed identity (MSI), so no secrets are needed in the workflow.

## Usage

1. Deploy the runner infrastructure first (main module)
2. Store GitHub App secrets in Key Vault and register the webhook
3. Trigger manually: **Actions → Demo Storage Terraform → Run workflow** (check "apply" to create resources)

## Files

```
├── main.tf             # Resource group + storage account
├── outputs.tf          # Resource names for verification
├── providers.tf        # AzureRM + Random providers
├── variables.tf        # Configurable names and location
├── versions.tf         # Provider version constraints
└── terraform.tfvars    # Default values (subscription_id set via env var)
```

> This example uses local state by design — it's a throwaway test, not a persistent deployment.
