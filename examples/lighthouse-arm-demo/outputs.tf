output "artifact_storage_resource_group_name" {
  description = "Dedicated resource group containing customer-facing Lighthouse artifacts."
  value       = azurerm_resource_group.artifacts.name
}

output "artifact_storage_account_name" {
  description = "Dedicated storage account containing Lighthouse artifacts; never the Terraform state account."
  value       = azurerm_storage_account.artifacts.name
}

output "artifact_storage_container_name" {
  description = "Private container holding immutable customer/version artifact paths."
  value       = azurerm_storage_container.artifacts.name
}

output "artifact_container_url" {
  description = "Private container URL. It grants no access by itself."
  value       = "${azurerm_storage_account.artifacts.primary_blob_endpoint}${azurerm_storage_container.artifacts.name}"
}

output "publisher_principal_object_id" {
  description = "OIDC service-principal object ID granted blob data access to the dedicated artifact account."
  value       = data.azurerm_client_config.current.object_id
}

output "arm_template_json" {
  description = "Self-contained ARM template JSON keyed by customer. The workflow uploads these values without printing them."
  value = {
    for customer_key, lighthouse in module.lighthouse_arm :
    customer_key => lighthouse.arm_template_json
  }
}

output "arm_template_sha256" {
  description = "SHA-256 checksum of each exact ARM template string, keyed by customer."
  value = {
    for customer_key, lighthouse in module.lighthouse_arm :
    customer_key => lighthouse.arm_template_sha256
  }
}

output "suggested_artifact_names" {
  description = "Human-friendly local filename suggested by the module, keyed by customer."
  value = {
    for customer_key, lighthouse in module.lighthouse_arm :
    customer_key => lighthouse.suggested_artifact_name
  }
}

output "customer_count" {
  description = "Number of customer artifacts rendered by this configuration."
  value       = length(module.lighthouse_arm)
}
