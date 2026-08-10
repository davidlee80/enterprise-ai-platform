# Production environment root

Independent production state boundary. Production inputs, remote encrypted
state backend, locking, approvals, plan evidence, and apply identity must be
reviewed separately from dev/stage. Run only through an approved infrastructure
workflow with `terraform plan -var-file=<approved-prod.tfvars>` followed by a
reviewed saved-plan apply.

`production_domain`, `production_namespace`,
`production_certificate_issuer`, and `production_storage_class` are nullable
`TBD-019` root variables. Their repository defaults remain null. Supply them
only through reviewed, non-secret production variable inputs; fixture values are
not production configuration.

Rollback re-applies the last reviewed source revision and compatible non-secret
variable revision through a new plan. Stateful data rollback uses service-
specific restore/runbooks; it must never use destructive state edits or copy
development state into production.
