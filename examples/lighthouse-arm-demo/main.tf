# Provider-side publisher only. The ownership mode is deliberately fixed in
# code: changing an existing delegation between manual ARM and native Terraform
# is a migration with an access gap or import, not a workflow toggle.
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
