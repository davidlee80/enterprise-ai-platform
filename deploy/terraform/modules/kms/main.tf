terraform {
  required_version = ">= 1.6.0, < 2.0.0"
}

variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage, or prod."
  }
}

variable "configuration" {
  description = "Key-purpose and audited integration references; never key material."
  type = object({
    key_purposes                   = set(string)
    secret_manager_integration_ref = string
    break_glass_workflow_ref       = string
    rotation_policy_ref            = string
  })

  validation {
    condition = (
      contains(var.configuration.key_purposes, "envelope-encryption") &&
      length(var.configuration.secret_manager_integration_ref) > 0 &&
      length(var.configuration.break_glass_workflow_ref) > 0 &&
      length(var.configuration.rotation_policy_ref) > 0
    )
    error_message = "KMS requires envelope-encryption plus reviewed Secret Manager, break-glass, and rotation policy references."
  }
}

output "contract" {
  value = {
    environment                    = var.environment
    key_purposes                   = sort(tolist(var.configuration.key_purposes))
    secret_manager_integration_ref = var.configuration.secret_manager_integration_ref
    break_glass_workflow_ref       = var.configuration.break_glass_workflow_ref
    rotation_policy_ref            = var.configuration.rotation_policy_ref
    application_credentials        = "secret_ref_or_short_lived_only"
    key_material_in_terraform      = false
    cloud_provider_status          = "TBD-011"
    secret_manager_status          = "TBD-012"
  }
}
