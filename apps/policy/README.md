# Policy

Control Plane policy lifecycle and compilation boundary. Runtime decisions must
be structured and tenant/version scoped; a policy engine product is not selected
by this bootstrap.

## Ownership metadata

| Field | Value |
|---|---|
| Owner | `TBD-018` |
| SLO | [Placeholder](../../ops/slo/README.md) |
| Runbook | [Placeholder](../../ops/runbooks/README.md) |
| Upgrade window | `TBD; assign with the runtime owner` |
| Data retention responsibility | `TBD if persistent data is introduced; none in TASK-M0-001` |

Cross-domain integration must use stable APIs or versioned events. Source is
traceable by Git revision; release version topology remains TBD under
`REQ-REP-006`.

## Data Plane Policy Decision boundary

The versioned [`Policy Boundary v1`](../../docs/contracts/policy-decisions/policy-boundary.v1.json)
consumes an authenticated, tenant-bound principal plus published policy context
and emits a structured decision. The conformance mock covers tenant status,
model/region allowlists, projected monthly budget, and typed obligations without
selecting the production policy runtime (`TBD-004`).

Only an `allow` outcome can proceed toward the Router. `deny` carries a
structured denial reason; `indeterminate` preserves unresolved runtime/context
failure so `TBD-017` is not replaced with a hard-coded resource policy.
