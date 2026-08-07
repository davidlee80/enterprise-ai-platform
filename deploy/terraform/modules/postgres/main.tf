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

variable "network_contract" {
  type = any
}

variable "kms_contract" {
  type = any
}

variable "configuration" {
  description = "PostgreSQL durability and logical-domain requirements; never credentials."
  type = object({
    engine_version        = string
    capacity_profile_ref  = string
    high_availability     = bool
    backup_retention_days = number
    logical_databases     = set(string)
    encryption_key_ref    = string
  })

  validation {
    condition = (
      length(var.configuration.engine_version) > 0 &&
      length(var.configuration.capacity_profile_ref) > 0 &&
      var.configuration.backup_retention_days > 0 &&
      length(var.configuration.encryption_key_ref) > 0 && alltrue([
        for required in ["control-plane", "usage", "billing", "audit"] :
        contains(var.configuration.logical_databases, required)
      ])
    )
    error_message = "PostgreSQL requires reviewed version/capacity references, retention, encryption, and separated control-plane/usage/billing/audit logical databases."
  }
}

output "contract" {
  value = {
    environment           = var.environment
    engine_version        = var.configuration.engine_version
    capacity_profile_ref  = var.configuration.capacity_profile_ref
    high_availability     = var.configuration.high_availability
    backup_retention_days = var.configuration.backup_retention_days
    logical_databases     = sort(tolist(var.configuration.logical_databases))
    encryption_key_ref    = var.configuration.encryption_key_ref
    network               = var.network_contract
    kms                   = var.kms_contract
    credentials           = "secret_ref_or_short_lived_only"
    provider_status       = "TBD-011"
  }
}
