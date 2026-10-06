resource "random_string" "storage_suffix" {
  length  = 8
  upper   = false
  lower   = true
  numeric = true
  special = false
}

data "azurerm_client_config" "current" {}

# Artifact delivery has a different audience and lifecycle from Terraform state,
# so it gets a dedicated resource group and storage account. This root's state
# remains in the internal state account under lighthouse-artifacts.tfstate.
resource "azurerm_resource_group" "artifacts" {
  name     = var.artifact_storage_resource_group_name
  location = var.artifact_storage_location

  tags = {
    workload  = "azure-lighthouse"
    purpose   = "customer-artifacts"
    managedBy = "terraform"
  }
}

resource "azurerm_storage_account" "artifacts" {
  name                     = "${var.artifact_storage_account_name_prefix}${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.artifacts.name
  location                 = azurerm_resource_group.artifacts.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.artifact_retention_days
    }

    container_delete_retention_policy {
      days = var.artifact_retention_days
    }
  }

  tags = {
    workload  = "azure-lighthouse"
    purpose   = "customer-artifacts"
    managedBy = "terraform"
  }
}

# The account contains only customer artifacts, so account-scoped data access is
# still isolated from Terraform state while avoiding a container/RBAC bootstrap
# cycle. The OIDC identity applying this root needs roleAssignments/write.
resource "azurerm_role_assignment" "publisher" {
  scope                = azurerm_storage_account.artifacts.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "ServicePrincipal"
}

# Azure RBAC is eventually consistent. Delay first-time container creation and
# retain a workflow-side readiness retry before publishing blobs.
resource "time_sleep" "publisher_rbac" {
  depends_on      = [azurerm_role_assignment.publisher]
  create_duration = "30s"
}

resource "azurerm_storage_container" "artifacts" {
  name                  = var.artifact_storage_container_name
  storage_account_id    = azurerm_storage_account.artifacts.id
  container_access_type = "private"

  depends_on = [time_sleep.publisher_rbac]
}

# Provider-side renderer only. Ownership mode is fixed in code: changing a live
# delegation between manual ARM and native Terraform is a migration, not a toggle.
module "lighthouse_arm" {
  for_each = var.customers

  source = "github.com/patrickthor/JSONARM-lighthouse-manifesto?ref=de3ab5f6f344ca283131b4a9d1e2b915a9d1ff69"

  artifact_version = var.artifact_version
  deployment_mode  = "arm"
  scope            = null

  delegation = merge(each.value, {
    managing_tenant_id = var.managing_tenant_id
  })
}
