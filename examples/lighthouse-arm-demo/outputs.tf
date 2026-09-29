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
