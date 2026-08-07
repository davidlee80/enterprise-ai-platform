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

variable "network_contract" {
  description = "Validated output from the network module."
  type        = any
}

variable "configuration" {
  description = "Cloud-neutral cluster and independent node-pool requirements."
  type = object({
    kubernetes_version = string
    node_pools = map(object({
      workload_class = string
      minimum_size   = number
      maximum_size   = number
      labels         = map(string)
      taints = list(object({
        key    = string
        value  = string
        effect = string
      }))
    }))
  })

  validation {
    condition = (
      length(var.configuration.kubernetes_version) > 0 &&
      contains(keys(var.configuration.node_pools), "data-plane") &&
      contains(keys(var.configuration.node_pools), "runtime") && alltrue([
        for pool in values(var.configuration.node_pools) :
        pool.minimum_size >= 0 && pool.maximum_size >= pool.minimum_size &&
        contains(["data-plane", "control-plane", "runtime", "observability"], pool.workload_class) && alltrue([
          for taint in pool.taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], taint.effect)
        ])
      ])
    )
    error_message = "node_pools must include independent data-plane and runtime pools with valid sizes, workload classes, and taint effects."
  }
}

output "contract" {
  description = "Cluster capacity contract consumed by a future provider adapter."
  value = {
    environment        = var.environment
    kubernetes_version = var.configuration.kubernetes_version
    node_pools         = var.configuration.node_pools
    network            = var.network_contract
    gateway_baseline = {
      replicas               = 3
      container_port         = 8080
      cpu_request_millicores = 500
      memory_request_mib     = 512
      cpu_limit_cores        = 2
      memory_limit_mib       = 2048
      requires_pdb           = true
      requires_spread        = true
    }
    namespace_status     = "TBD-019"
    storage_class_status = "TBD-019"
    provider_status      = "TBD-011"
  }
}
