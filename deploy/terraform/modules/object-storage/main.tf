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

variable "kms_contract" {
  type = any
}

variable "configuration" {
  description = "Domain-owned object-storage contracts. Bucket names remain environment inputs."
  type = object({
    stores = map(object({
      data_domain           = string
      purpose               = string
      versioning_enabled    = bool
      public_access_blocked = bool
      encryption_key_ref    = string
    }))
  })

  validation {
    condition = length(var.configuration.stores) > 0 && alltrue([
      for store in values(var.configuration.stores) :
      length(store.data_domain) > 0 && length(store.purpose) > 0 &&
      store.versioning_enabled && store.public_access_blocked &&
      length(store.encryption_key_ref) > 0
    ])
    error_message = "Every object store requires a domain, purpose, versioning, blocked public access, and encryption reference."
  }
}

output "contract" {
  value = {
    environment               = var.environment
    stores                    = var.configuration.stores
    kms                       = var.kms_contract
    gateway_direct_rag_access = false
    knowledge_domain_access   = "stable_versioned_interface_only"
    credentials               = "secret_ref_or_short_lived_only"
    provider_status           = "TBD-011"
  }
}

