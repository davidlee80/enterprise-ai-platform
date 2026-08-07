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
  description = "Event-domain topic contracts. Topic names remain environment inputs."
  type = object({
    encryption_key_ref = string
    topics = map(object({
      event_domain           = string
      schema_version         = number
      partition_key_contract = string
      retry_topic            = string
      dead_letter_topic      = string
    }))
  })

  validation {
    condition = (
      length(var.configuration.encryption_key_ref) > 0 &&
      length(var.configuration.topics) > 0 && alltrue([
        for topic in values(var.configuration.topics) :
        length(topic.event_domain) > 0 && topic.schema_version >= 1 &&
        floor(topic.schema_version) == topic.schema_version &&
        length(topic.partition_key_contract) > 0 &&
        length(topic.retry_topic) > 0 && length(topic.dead_letter_topic) > 0
      ])
    )
    error_message = "Every event-domain topic requires an integer schema version, partition-key contract, retry topic, DLQ, and encryption reference."
  }
}

output "contract" {
  value = {
    environment              = var.environment
    topics                   = var.configuration.topics
    encryption_key_ref       = var.configuration.encryption_key_ref
    network                  = var.network_contract
    kms                      = var.kms_contract
    idempotent_consumers     = true
    at_least_once_delivery   = true
    schema_meaning_immutable = true
    credentials              = "secret_ref_or_short_lived_only"
    provider_status          = "TBD-011"
  }
}
