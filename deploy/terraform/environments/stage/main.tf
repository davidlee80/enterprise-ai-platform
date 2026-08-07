terraform {
  required_version = ">= 1.6.0, < 2.0.0"
}

module "platform" {
  source = "../../modules/platform-environment"

  environment   = "stage"
  configuration = var.configuration
}

