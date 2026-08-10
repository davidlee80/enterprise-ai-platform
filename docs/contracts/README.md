# Public contracts

This directory is the canonical home for machine-readable contracts shared
across application and package boundaries.

| Contract type | Directory | Implemented by |
|---|---|---|
| OpenAPI | [`openapi/`](openapi/README.md) | `TASK-M2-001` / `TASK-API-001` |
| Admin write idempotency | [`idempotency/`](idempotency/README.md) | `TBD-005` contract extension point / `REQ-API-007` |
| Admin list pagination | [`pagination/`](pagination/README.md) | `TBD-006` API design-review boundary / `REQ-API-006` |
| SDK generation pipeline | [`../../packages/sdk/contracts/`](../../packages/sdk/contracts/) | `TBD-007` pipeline boundary / `REQ-API-009` |
| Public HTTP error semantics | [`errors/`](errors/README.md) | `TBD-008` status-only boundary / `REQ-API-004` |
| Event schemas | [`events/`](events/README.md) | Event-producing tasks beginning with `TASK-M1-002` |
| Usage Event schemas | [`events/usage/`](events/usage/README.md) | `TASK-M2-007` |
| Runtime Snapshot schemas | [`runtime-snapshots/`](runtime-snapshots/README.md) | `TASK-M1-003` and `TASK-M1-004` |
| Runtime Snapshot staleness policy | [`runtime-snapshots/`](runtime-snapshots/README.md) | `TBD-016` configurability / `REQ-GEN-010` |
| Policy Decision schemas | [`policy-decisions/`](policy-decisions/README.md) | `TASK-M2-003` |
| Router Plugin schemas | [`router/`](router/README.md) | `TASK-M2-004` |
| Provider canary schemas | [`provider-canary/`](provider-canary/README.md) | `TBD-014` configurability / `REQ-REL-004` / `REQ-REL-006` |
| Deprecation schemas | [`deprecation/`](deprecation/README.md) | `TBD-015` workflow fields / `REQ-REL-002` / `REQ-REL-007` |
| Provider Adapter schemas | [`providers/`](providers/README.md) | `TASK-M2-005` |
| Retry/Fallback schemas | [`retry-fallback/`](retry-fallback/README.md) | `TASK-M2-006` |
| Secret reference schemas | [`secrets/`](secrets/README.md) | `TBD-012` abstraction / `REQ-GEN-012` / `REQ-IAC-007` |
| Architecture decisions | [`../adr/`](../adr/README.md) | The task requiring the decision |

`TASK-M0-002` defines storage boundaries only. It does not publish a contract or
select unresolved production semantics. A contract becomes authoritative only
when its owning task adds a machine-readable artifact, validation, compatibility
evidence, and an explicit version.

Contracts must not contain credentials, internal Provider endpoints, or
plaintext Provider keys. Breaking changes require an explicit compatibility and
migration path; published versions remain available for rollback or replay as
required by their owning domain.
