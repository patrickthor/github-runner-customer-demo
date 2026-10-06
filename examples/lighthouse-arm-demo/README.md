# Azure Lighthouse ARM Artifact Publisher

This is the provider-side consumer of [`JSONARM-lighthouse-manifesto`](https://github.com/patrickthor/JSONARM-lighthouse-manifesto). It renders one self-contained ARM template per configured customer and the workflow publishes each template to private Azure Blob Storage. A customer downloads the selected JSON and uploads it through **Azure Portal → Deploy a custom template → Build your own template in the editor → Load file**, or **Service providers → Add offer via template**.

This root is permanently fixed to `deployment_mode = "arm"`. It never creates a Lighthouse registration in a customer subscription and needs no customer credentials. Terraform customers instead consume the module in `terraform` mode from their own customer-side repository/state. Do not manage one delegation through both paths.

## Configuration ownership

`terraform.tfvars` is the committed governance record. It owns each customer key, offer metadata, managing-tenant principal/approver UUIDs, permanent roles, eligible roles, activation duration, and MFA/approval policy. The shared managing tenant ID and artifact version are runtime values so they are not repeated for every customer.

The Lighthouse module owns the authoritative nested schema and validation. It also owns the built-in role UUID map, so this root names `Reader` and `Contributor` rather than copying role UUIDs.

`customers = {}` is a valid safe initial state and renders nothing. Replace it with real managing-tenant group UUIDs before publishing an artifact intended for deployment. The access-vending module does not yet have an `azure_lighthouse` group-only mechanism, so do not reuse one of its current `azure_pim` groups: that would create parallel direct-PIM and Lighthouse access paths.

## Publishing

Run `deploy-runners.yml` with `action = apply` first. It builds `runner-image/Dockerfile` into ACR as `actions-runner:latest`; that repository-owned image contains Azure CLI. Existing ACI jobs are ephemeral, so the next queued job pulls the rebuilt image. The publishing workflow fails before login with a targeted message if an older image without `az` is still being used.

Then run **Actions → Publish Lighthouse ARM Artifacts**.

- `plan` validates and previews rendering without uploading.
- `publish` renders and uploads immutable blobs.
- `artifact_version` is optional; the workflow uses the full Git commit SHA when omitted.

Required secrets:

- `AZURE_CLIENT_ID`, or optional preferred `AZURE_VENDING_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

Required repository variables:

- `STATE_STORAGE_ACCOUNT` — reused as the remote storage account
- `LIGHTHOUSE_ARTIFACT_CONTAINER` — optional, defaults to `lighthouse-artifacts`
- `STATE_CONTAINER` and `RUNNER_STATE_CONTAINER` are checked so neither can accidentally be used as the artifact container

The selected OIDC identity needs `Storage Blob Data Contributor` on the storage account or the dedicated artifact container. The workflow creates the private container if it does not exist and uploads to:

```text
<customer-key>/<artifact-version>/lighthouse.json
```

An existing blob is accepted only when its stored SHA-256 metadata matches the newly rendered template. A different payload at the same customer/version fails instead of overwriting history. No SAS token is generated or logged.

This root intentionally uses ephemeral local Terraform state: it creates no infrastructure, and the immutable remote blob is the durable product. Deleting a blob does not remove a Lighthouse delegation already deployed by a customer; authorization changes require a new artifact version and customer redeployment.
