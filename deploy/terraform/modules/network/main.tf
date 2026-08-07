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
  description = "Reviewed provider-neutral network boundaries."
  type = object({
    address_space        = string
    private_subnet_cidrs = set(string)
  })

  validation {
    condition = can(cidrnetmask(var.configuration.address_space)) && alltrue([
      for cidr in var.configuration.private_subnet_cidrs : can(cidrnetmask(cidr))
    ]) && length(var.configuration.private_subnet_cidrs) > 0
    error_message = "address_space and every private subnet must be valid CIDRs, with at least one private subnet."
  }
}

output "contract" {
  description = "Provider adapter input; contains no provisioned resource IDs."
  value = {
    environment          = var.environment
    address_space        = var.configuration.address_space
    private_subnet_cidrs = sort(tolist(var.configuration.private_subnet_cidrs))
    public_ingress       = "not_selected"
    provider_status      = "TBD-011"
  }
}

