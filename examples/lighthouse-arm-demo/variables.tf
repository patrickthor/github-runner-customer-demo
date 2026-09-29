variable "artifact_storage_subscription_id" {
  description = "Subscription containing the remote artifact storage account. Supplied by CI, not committed tfvars."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.artifact_storage_subscription_id))
    error_message = "artifact_storage_subscription_id must be a UUID."
  }
}

variable "artifact_version" {
  description = "Immutable storage-path-safe artifact version supplied by the publishing workflow."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*$", var.artifact_version))
    error_message = "artifact_version must start with an alphanumeric character and contain only letters, numbers, dots, underscores, or hyphens."
  }
}

variable "managing_tenant_id" {
  description = "Service-provider Entra tenant ID shared by every generated delegation. Supplied by CI."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.managing_tenant_id))
    error_message = "managing_tenant_id must be a UUID."
  }
}

variable "customers" {
  description = <<-EOT
    Committed Lighthouse governance records keyed by a stable, storage-safe
    customer identifier. This root intentionally leaves the nested value as any:
    the pinned Lighthouse module owns and validates the authoritative schema.
  EOT
  type        = any
  default     = {}

  validation {
    condition = alltrue([
      for customer_key in keys(var.customers) :
      can(regex("^[a-z0-9][a-z0-9-]*$", customer_key))
    ])
    error_message = "Every customer key must contain only lowercase letters, numbers, and hyphens."
  }
}
