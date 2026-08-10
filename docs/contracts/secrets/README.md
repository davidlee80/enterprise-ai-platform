# Secret reference and resolution contracts

This directory implements the `TBD-012` development handling: applications and
Control Plane configuration exchange opaque `secret_ref` values, while the
Secret Manager product remains unselected.

- `secret-reference.v1.schema.json` defines the tenant/config-version-scoped
  opaque reference. It deliberately has no URI pattern, prefix, product enum, or
  storage location.
- `secret-resolution-request.v1.schema.json` and
  `secret-resolution-decision.v1.schema.json` define structured resolution
  context and safe outcomes. Decisions never contain the reference, credential,
  endpoint, raw error, or stack trace.
- `secret-manager-binding.v1.schema.json` is the versioned configuration entry
  point for a future reviewed product adapter, identity, audit, rotation, and
  break-glass workflow.
- `secret-manager-boundary.v1.json` keeps all current product bindings and
product-specific policies null.

Break-glass approval uses the product-neutral coordination contract under
[`ops/coordination/`](../../../ops/coordination/README.md); its concrete
approval system and role bindings remain `TBD-020`.

Credential material may be delivered only in process to the consuming adapter.
It must never be serialized, persisted, logged, measured, returned in errors, or
placed in Terraform state. Tenant, config-version, access, and rotation checks
precede delivery. Audit is emitted as an asynchronous, non-blocking event;
enqueue rejection is observable but does not put Audit persistence in the model
invocation critical path. Manager, rotation, or delivery failures do not release
credential material.

The binding registry may later contain one or more reviewed products and does
not impose one Secret Manager across every tenant or environment. Rotation
schedule, overlap/revocation behavior, credential caching, lease renewal, exact
reference syntax, and break-glass approval tooling remain `TBD-012`.

Run from the repository root:

```powershell
pwsh -NoLogo -NoProfile -File ./docs/contracts/secrets/secret-manager.conformance.ps1
pwsh -NoLogo -NoProfile -File ./scripts/task.ps1 test-tbd-012
```
