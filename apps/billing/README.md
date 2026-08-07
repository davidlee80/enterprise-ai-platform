# Billing

Billing and usage-aggregation application boundary. Usage processing must be
asynchronous and must not block the online model request path.

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

## Usage Event Boundary v1

The versioned [`UsageObserved` contract](../../docs/contracts/events/usage/README.md)
is accepted only through an asynchronous, idempotent consumer. Duplicate
`event_id` or tenant-scoped `usage_record_id` values do not create a second
usage fact. Event backlog, publisher retry, and consumer persistence never block
the online Gateway response.

Consumer failures support explicit `retry` and `dead_letter` actions without
committing idempotency state. Retry schedule, maximum attempts, and DLQ
destination remain configuration/ADR inputs rather than hard-coded defaults.

This task does not create the pending `usage` aggregation table or decide time
buckets, pricing precision, currency authority, retention, broker/topic,
partition key, retry/DLQ, or buffer durability. Those remain domain schema and
ADR inputs. The conformance consumer uses only in-memory fakes and performs no
Billing SQL write.
