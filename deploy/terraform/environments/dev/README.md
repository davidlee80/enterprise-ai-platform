# Development environment root

Independent development state boundary. Supply a reviewed non-secret variable
file outside source control, then run `terraform plan -var-file=<approved-dev.tfvars>`.
No default CIDR, version, node sizing, topic, bucket, DNS domain, credential, or
Secret Manager product is selected by this root.

