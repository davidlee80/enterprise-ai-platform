terraform {
  required_version = ">= 1.6.0, < 2.0.0"
}

module "platform" {
  source = "../../modules/platform-environment"

  environment   = "prod"
  configuration = var.configuration
}

variable "production_domain" {
  description = "Reviewed production domain; null while TBD-019 is unresolved."
  type        = string
  default     = null
  nullable    = true
}

variable "production_namespace" {
  description = "Reviewed production Kubernetes Namespace; null while TBD-019 is unresolved."
  type        = string
  default     = null
  nullable    = true
}

variable "production_certificate_issuer" {
  description = "Reviewed production certificate issuer reference; null while TBD-019 is unresolved."
  type        = string
  default     = null
  nullable    = true
}

variable "production_storage_class" {
  description = "Reviewed production StorageClass; null while TBD-019 is unresolved."
  type        = string
  default     = null
  nullable    = true
}
