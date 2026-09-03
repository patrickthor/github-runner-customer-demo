# ==============================================================================
# Basic example — minimal module usage for consuming projects
#
# All values are driven by variables (set via GitHub repo variables + the
# workflow's "Generate terraform.tfvars" step). No manual editing needed.
# ==============================================================================

module "runners" {
  source = "github.com/patrickthor/github-runners//modules/runners?ref=main"

  # Core naming — generates all resource names automatically
  workload    = var.workload
  environment = var.environment
  instance    = var.instance
  location    = var.location

  # GitHub configuration
  github_org  = var.github_org
  github_repo = var.github_repo

  # Key Vault secret names
  github_app_id_secret_name              = var.github_app_id_secret_name
  github_app_installation_id_secret_name = var.github_app_installation_id_secret_name
  github_app_private_key_secret_name     = var.github_app_private_key_secret_name

  # Runner identity roles (empty = least privilege)
  runner_workload_roles = var.runner_workload_roles
}

# ==============================================================================
# Outputs — useful for webhook setup and debugging
# ==============================================================================

output "function_app_name" {
  description = "Function App name (needed by the deploy workflow)"
  value       = module.runners.function_app_name
}

output "function_app_hostname" {
  description = "Use this hostname to configure the GitHub webhook"
  value       = module.runners.function_app_default_hostname
}

output "resource_group_name" {
  value = module.runners.resource_group_name
}

output "acr_login_server" {
  description = "Push your runner image here"
  value       = module.runners.acr_login_server
}

output "key_vault_uri" {
  description = "Store GitHub App secrets here"
  value       = module.runners.key_vault_uri
}

output "runner_pull_principal_id" {
  description = <<-EOT
    Principal ID of the runner identity that ACI containers run as.

    The deploy workflow uses this to grant the runners data-plane access to their
    own Terraform state container, so jobs on the runners can use a remote
    backend without being able to read the platform's or access vending's state.
  EOT
  value       = module.runners.runner_pull_identity.principal_id
}
