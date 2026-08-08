# Cloud-neutral Terraform topology

`TASK-M3-003` defines validated infrastructure contracts without selecting a
cloud provider. The required capability modules are:

- `modules/network`
- `modules/kubernetes`
- `modules/postgres`
- `modules/redis`
- `modules/kafka`
- `modules/object-storage`
- `modules/kms`
- `modules/dns`

`modules/platform-environment` is the shared composition layer reused by the
`environments/dev`, `environments/stage`, and `environments/prod` roots. Each
environment has an independent root/state boundary and accepts its own reviewed
non-secret variable file.

These modules intentionally contain no AWS, Azure, GCP, Vault, or other vendor
resource. `TBD-011` and `TBD-012` must be resolved by reviewed ADRs before
provider resources, remote state backends, Secret Manager integration, or
provider-specific identity are added. Passing `terraform validate` proves the
module contracts and composition, not that infrastructure has been provisioned.

No variable accepts plaintext credentials. KMS, Secret Manager, break-glass,
and encryption inputs are references or policy identifiers only. Applications
must receive `secret_ref` or short-lived credentials through a separately
audited runtime integration.

Run the complete conformance gate with:

```bash
./scripts/task.sh test-m3-003
```

Environment initialization uses `terraform init -backend=false`; a reviewed,
encrypted, locked remote backend remains required before any real environment
plan or apply. Normal production delivery will be owned by `TASK-M3-004` GitOps
and an approved infrastructure workflow, never ad-hoc application CI.
