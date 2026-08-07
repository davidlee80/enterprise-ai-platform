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
  description = "Reviewed DNS zone purposes without selecting production domains."
  type = object({
    zones = map(object({
      purpose    = string
      visibility = string
    }))
  })

  validation {
    condition = length(var.configuration.zones) > 0 && alltrue([
      for zone in values(var.configuration.zones) :
      length(zone.purpose) > 0 && contains(["private", "public"], zone.visibility)
    ])
    error_message = "Every DNS zone requires a purpose and private/public visibility."
  }
}

output "contract" {
  value = {
    environment        = var.environment
    zones              = var.configuration.zones
    domain_status      = "TBD-019"
    certificate_status = "TBD-019"
    provider_status    = "TBD-011"
  }
}

