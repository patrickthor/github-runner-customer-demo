variable "artifact_storage_subscription_id" {
  description = "Subscription in which the dedicated Lighthouse artifact storage account is created. Supplied by CI."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.artifact_storage_subscription_id))
    error_message = "artifact_storage_subscription_id must be a UUID."
  }
}

variable "artifact_storage_resource_group_name" {
  description = "Dedicated resource group for Lighthouse artifact storage. Supplied by CI."
  type        = string

  validation {
    condition     = length(trimspace(var.artifact_storage_resource_group_name)) > 0 && length(var.artifact_storage_resource_group_name) <= 90
    error_message = "artifact_storage_resource_group_name must contain 1-90 characters."
  }
}

variable "artifact_storage_account_name" {
  description = "Globally unique name of the dedicated Lighthouse artifact storage account. Supplied by CI."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.artifact_storage_account_name))
    error_message = "artifact_storage_account_name must contain 3-24 lowercase letters or numbers."
  }
}

variable "artifact_storage_container_name" {
  description = "Private container holding versioned Lighthouse ARM artifacts."
  type        = string
  default     = "lighthouse-artifacts"

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.artifact_storage_container_name)) &&
      !strcontains(var.artifact_storage_container_name, "--")
    )
    error_message = "artifact_storage_container_name must be a valid 3-63 character lowercase Azure container name."
  }
}

variable "artifact_storage_location" {
  description = "Azure region for the dedicated artifact resource group and storage account."
  type        = string

  validation {
    condition     = trimspace(var.artifact_storage_location) != ""
    error_message = "artifact_storage_location must not be empty."
  }
}

variable "artifact_retention_days" {
  description = "Soft-delete retention for blobs and containers."
  type        = number
  default     = 30

  validation {
    condition     = var.artifact_retention_days >= 7 && var.artifact_retention_days <= 365
    error_message = "artifact_retention_days must be between 7 and 365."
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
    the Lighthouse module owns and validates the authoritative schema.
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
