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
  description = "Redis availability, encryption, and explicit semantic-cache policy."
  type = object({
    high_availability  = bool
    encryption_key_ref = string
    semantic_cache = object({
      enabled    = bool
      policy_ref = optional(string)
    })
  })

  validation {
    condition = length(var.configuration.encryption_key_ref) > 0 && (
      !var.configuration.semantic_cache.enabled ||
      try(length(var.configuration.semantic_cache.policy_ref) > 0, false)
    )
    error_message = "Redis requires an encryption reference, and semantic cache requires an explicit reviewed policy reference when enabled."
  }
}

output "contract" {
  value = {
    environment           = var.environment
    high_availability     = var.configuration.high_availability
    encryption_key_ref    = var.configuration.encryption_key_ref
    semantic_cache        = var.configuration.semantic_cache
    network               = var.network_contract
    kms                   = var.kms_contract
    cache_layers          = ["L1-process-memory", "L2-redis", "L3-semantic-explicit-only"]
    cache_key_isolation   = ["tenant_id", "config_version"]
    atomic_state_required = true
    credentials           = "secret_ref_or_short_lived_only"
    provider_status       = "TBD-011"
  }
}

