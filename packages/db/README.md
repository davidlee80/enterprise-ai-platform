# DB

Reusable database connection, transaction, and migration primitives. Domain
repositories remain owned by their applications; this package must not become a
cross-domain path for reading or writing business tables.

The versioned PostgreSQL baseline and its forward/rollback policy are documented
under [migrations/](migrations/README.md). Fields not explicitly confirmed by the
requirements remain in the migration [TBD register](migrations/TBD.md), not in
executable SQL.

The transactional event persistence and asynchronous publisher coordination
boundary is documented under [outbox/](outbox/README.md). Broker adapters remain
outside this shared database package and must not turn it into cross-domain
business logic.

## Ownership metadata

| Field | Value |
|---|---|
| Owner | `TBD-018` |
| SLO | [Placeholder](../../ops/slo/README.md) |
| Runbook | [Placeholder](../../ops/runbooks/README.md) |
| Upgrade window | `TBD; assign with the component owner` |
| Data retention responsibility | `Not applicable at bootstrap; database ownership is assigned with later schemas` |

Source is traceable by Git revision; release version topology remains TBD under
`REQ-REP-006`.
