# Public contracts

This directory is the canonical home for machine-readable contracts shared
across application and package boundaries.

| Contract type | Directory | Implemented by |
|---|---|---|
| OpenAPI | [`openapi/`](openapi/README.md) | `TASK-M2-001` / `TASK-API-001` |
| Event schemas | [`events/`](events/README.md) | Event-producing tasks beginning with `TASK-M1-002` |
| Usage Event schemas | [`events/usage/`](events/usage/README.md) | `TASK-M2-007` |
| Runtime Snapshot schemas | [`runtime-snapshots/`](runtime-snapshots/README.md) | `TASK-M1-003` and `TASK-M1-004` |
| Policy Decision schemas | [`policy-decisions/`](policy-decisions/README.md) | `TASK-M2-003` |
| Router Plugin schemas | [`router/`](router/README.md) | `TASK-M2-004` |
| Provider Adapter schemas | [`providers/`](providers/README.md) | `TASK-M2-005` |
| Retry/Fallback schemas | [`retry-fallback/`](retry-fallback/README.md) | `TASK-M2-006` |
| Architecture decisions | [`../adr/`](../adr/README.md) | The task requiring the decision |

`TASK-M0-002` defines storage boundaries only. It does not publish a contract or
select unresolved production semantics. A contract becomes authoritative only
when its owning task adds a machine-readable artifact, validation, compatibility
evidence, and an explicit version.

Contracts must not contain credentials, internal Provider endpoints, or
plaintext Provider keys. Breaking changes require an explicit compatibility and
migration path; published versions remain available for rollback or replay as
required by their owning domain.
