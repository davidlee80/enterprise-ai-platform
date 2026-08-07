# Cache

Reusable cache abstractions and adapters. Cache keys and entries must preserve
tenant and configuration-version boundaries, and caches must not become a unique
source of business truth.

The [Redis Runtime Snapshot Store](snapshot-store/README.md) provides immutable
version reads, compare-and-swap publication, a tenant-scoped current pointer,
and rollback for `TASK-M1-003`.

The [Data Plane Snapshot Consumer](snapshot-consumer/README.md) consumes
tenant-scoped version notifications, validates complete immutable Snapshots,
atomically exchanges the active in-memory reference, retains the last validated
version during fetch failures, and emits version/staleness telemetry for
`TASK-M1-004`.

This package must not contain domain repositories or directly read/write another
domain's business tables.

## Ownership metadata

| Field | Value |
|---|---|
| Owner | `TBD-018` |
| SLO | [Placeholder](../../ops/slo/README.md) |
| Runbook | [Placeholder](../../ops/runbooks/README.md) |
| Upgrade window | `TBD; assign with the component owner` |
| Data retention responsibility | `Not applicable at bootstrap; re-evaluate if persistence is introduced` |

Source is traceable by Git revision; release version topology remains TBD under
`REQ-REP-006`.
