terraform {
  required_version = ">= 1.6.0, < 2.0.0"
}

variable "environment" {
  description = "Environment identity."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage, or prod."
  }
}

variable "configuration" {
  description = "Reviewed environment configuration composed by strict leaf modules."
  type        = any
  nullable    = false
}

module "network" {
  source = "../network"

  environment   = var.environment
  configuration = var.configuration.network
}

module "kms" {
  source = "../kms"

  environment   = var.environment
  configuration = var.configuration.kms
}

module "kubernetes" {
  source = "../kubernetes"

  environment      = var.environment
  network_contract = module.network.contract
  configuration    = var.configuration.kubernetes
}

module "postgres" {
  source = "../postgres"

  environment      = var.environment
  network_contract = module.network.contract
  kms_contract     = module.kms.contract
  configuration    = var.configuration.postgres
}

module "redis" {
  source = "../redis"

  environment      = var.environment
  network_contract = module.network.contract
  kms_contract     = module.kms.contract
  configuration    = var.configuration.redis
}

module "kafka" {
  source = "../kafka"

  environment      = var.environment
  network_contract = module.network.contract
  kms_contract     = module.kms.contract
  configuration    = var.configuration.kafka
}

module "object_storage" {
  source = "../object-storage"

  environment   = var.environment
  kms_contract  = module.kms.contract
  configuration = var.configuration.object_storage
}

module "dns" {
  source = "../dns"

  environment   = var.environment
  configuration = var.configuration.dns
}

output "contracts" {
  description = "Validated, non-secret provider-adapter contracts."
  value = {
    network        = module.network.contract
    kubernetes     = module.kubernetes.contract
    postgres       = module.postgres.contract
    redis          = module.redis.contract
    kafka          = module.kafka.contract
    object_storage = module.object_storage.contract
    kms            = module.kms.contract
    dns            = module.dns.contract
  }
}

