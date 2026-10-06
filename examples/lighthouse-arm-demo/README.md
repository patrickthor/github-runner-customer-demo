# Azure Lighthouse ARM Artifact Publisher

This provider-side root consumes [`JSONARM-lighthouse-manifesto`](https://github.com/patrickthor/JSONARM-lighthouse-manifesto), renders one self-contained ARM template per configured subscription scope, and publishes each version to a dedicated private Azure Storage account. Customers download the selected JSON and upload it through **Azure Portal → Deploy a custom template → Build your own template in the editor → Load file**, or **Service providers → Add offer via template**.

This root is fixed to `deployment_mode = "arm"`. It never creates a Lighthouse registration in a customer subscription and needs no customer credentials. Terraform-capable customers use the module's native mode from their own customer-side repository/state. Never manage one delegation through both paths.

## Configuration ownership

`terraform.tfvars` is the committed governance record. It owns customer keys, offer metadata, managing-tenant principal/approver UUIDs, permanent roles, eligible roles, activation duration, and MFA/approval policy. The shared managing tenant ID, storage coordinates, and artifact version are runtime values rather than repeated customer data.

Every `customers` entry produces one subscription-scoped artifact. A logical customer with multiple subscriptions therefore has multiple entries and deployments. All committed UUIDs are synthetic test values until replaced with real managing-tenant object IDs.

## Dedicated storage boundary

Terraform manages a dedicated artifact resource group, storage account, and private container. The account has:

- Anonymous blob access disabled.
- Shared-key authentication disabled.
- HTTPS and TLS 1.2 required.
- Microsoft Entra authentication as the default.
- Blob versioning enabled.
- Blob and container soft delete enabled for 30 days by default.
- `Storage Blob Data Contributor` granted to the OIDC publishing identity.

The account's public endpoint remains enabled because the ephemeral ACI runner is not currently integrated with a private endpoint/VNet. The container is private.

The root's Terraform state remains in the existing internal state account, using the separate key:

```text
lighthouse-artifacts.tfstate
```

Artifact JSON never goes into the state account. Previously published blobs in the old state storage account are not moved or deleted automatically; verify new publication before cleaning them up manually.

## Required GitHub configuration

Secrets:

- `AZURE_CLIENT_ID`, or preferred optional `AZURE_VENDING_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID` — fallback subscription when a dedicated artifact/state subscription variable is omitted

Repository variables:

| Variable | Required | Purpose |
|---|---:|---|
| `LIGHTHOUSE_ARTIFACT_STORAGE_ACCOUNT` | yes | Globally unique dedicated storage account name |
| `LIGHTHOUSE_ARTIFACT_RESOURCE_GROUP` | yes | Dedicated artifact resource group |
| `LIGHTHOUSE_ARTIFACT_SUBSCRIPTION_ID` | no | Artifact subscription; defaults to `AZURE_SUBSCRIPTION_ID` |
| `LIGHTHOUSE_ARTIFACT_CONTAINER` | no | Private container; defaults to `lighthouse-artifacts` |
| `AZURE_LOCATION` | yes | Artifact account region |
| `STATE_RESOURCE_GROUP` | yes | Existing internal Terraform backend resource group |
| `STATE_STORAGE_ACCOUNT` | yes | Existing internal Terraform backend account |
| `STATE_CONTAINER` | no | Backend container; defaults to `tfstate` |
| `STATE_SUBSCRIPTION_ID` | no | Backend subscription; defaults to `AZURE_SUBSCRIPTION_ID` |

`LIGHTHOUSE_ARTIFACT_STORAGE_ACCOUNT` must differ from `STATE_STORAGE_ACCOUNT`; the workflow fails before Terraform initialization if they match.

The selected OIDC identity needs:

- `Contributor` on the artifact resource group/subscription to create storage resources.
- `User Access Administrator` or equivalent `roleAssignments/write` permission to grant itself blob data access.
- `Storage Blob Data Contributor` on the existing state account/container so Terraform can use the remote backend.

## Publishing

Run `deploy-runners.yml` with `action = apply` first so the self-hosted image contains Azure CLI. Then run **Actions → Publish Lighthouse ARM Artifacts**:

- `plan` validates the governance model and previews dedicated storage changes without publishing.
- `publish` applies storage changes and uploads immutable customer/version paths.
- Blank `artifact_version` uses the full consumer Git commit SHA.

Artifacts are uploaded to:

```text
<customer-key>/<artifact-version>/lighthouse.json
```

The workflow reads the account and container from Terraform outputs, retries while the first RBAC assignment propagates, verifies SHA-256, and refuses to overwrite an existing path with different content. Its summary prints the account, container, private blob URL, checksum, and exact authenticated download command. No SAS token is generated or logged.

Deleting a blob or the artifact account does not remove a Lighthouse delegation already deployed by a customer. Authorization changes require a new artifact version and customer redeployment.
