# Stage environment root

Independent pre-production state boundary. Supply a reviewed non-secret
variable file outside source control, then run
`terraform plan -var-file=<approved-stage.tfvars>`. Promotion must use reviewed
source and variables rather than copying mutable development state.

