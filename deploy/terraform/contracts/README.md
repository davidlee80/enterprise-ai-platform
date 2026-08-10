# Cloud provider selection contracts

These contracts implement the `TBD-011` development boundary without choosing
a cloud provider.

- `cloud-provider-selection.v1.schema.json` is the versioned configuration
  entry point for a future reviewed provider, locations, workload identity,
  remote state, and eight capability adapters.
- `cloud-provider-boundary.v1.json` records that every selection and adapter
  reference is currently null and provider planning/apply remain disabled.
- `cloud-provider-compatibility-baseline.v1.json` protects the provider-neutral
  module surface and unresolved fields.

The configuration schema deliberately has no provider enum. Each versioned
record represents a provider binding, so a reviewed registry may publish one or
more bindings without redefining the stable network, Kubernetes, PostgreSQL,
Redis, Kafka, object-storage, KMS, or DNS capability contracts. The core
topology does not require a single-provider architecture.

Run the provider-neutral gate from the repository root:

```powershell
pwsh -NoLogo -NoProfile -File ./deploy/terraform/cloud-provider-neutrality.conformance.ps1
pwsh -NoLogo -NoProfile -File ./scripts/task.ps1 test-tbd-011
```
