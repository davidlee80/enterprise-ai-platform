# Data Plane Runtime Snapshot Consumer

This package implements the `TASK-M1-004` consumption state machine and an
executable conformance reference. It does not select the backend language, web
framework, DDD directory convention, or dependency-injection framework. The
PowerShell/.NET implementation exists so the contract and concurrency behavior
can be tested before `TBD-001` and `TBD-002` are decided; a production runtime in
another language must pass equivalent tests.

## Publication and notification contract

Snapshot publication appends a compact notification to the tenant-scoped Redis
Stream in the same server-side script that stores the immutable version and
advances the current pointer:

```text
runtime-snapshot:{tenant_id}:notifications
```

The stream entry follows
[`snapshot-notification.v1.schema.json`](../../../docs/contracts/runtime-snapshots/snapshot-notification.v1.schema.json).
It carries identity, version, hash, activation time, and `PUBLISH` or `ROLLBACK`;
it never carries the full Snapshot or Provider credentials. No stream `MAXLEN`,
TTL, trimming interval, or production retention value is hard-coded.

Notification delivery is at-least-once. A runtime adapter must read the tenant
stream, may receive duplicates, and must reconcile the current pointer when it
starts or reconnects so missed wakeups cannot leave it permanently behind. The
adapter turns each stream entry into the JSON notification contract and calls
`Invoke-RuntimeSnapshotNotification`; `Sync-RuntimeSnapshotCurrent` implements
the startup/reconnect reconciliation against the current-pointer and immutable
version read interfaces. Redis client selection, consumer-group
topology, blocking-read interval, retry timing, and stream retention remain
deployment/runtime decisions rather than hidden defaults in this package.

## Consumer state transition

For every notification, the consumer:

1. validates the notification schema fields and tenant boundary;
2. ignores duplicate or stale publication notifications by version and hash;
3. confirms that the notification still matches the tenant current pointer;
4. fetches the complete immutable version using only the tenant and version;
5. validates stored metadata, exact SHA-256 hash, Snapshot JSON, core fields,
   tenant/version consistency, and credential-field safety;
6. builds a new immutable candidate object;
7. atomically exchanges the tenant's active in-memory reference;
8. exposes the active `config_version`, staleness, and propagation latency.

`AtomicSnapshotSlot.Exchange` is the only activation operation. A request first
calls `Get-RuntimeSnapshotLease` and keeps the returned object reference. New
requests capture the new reference after a swap, while already in-flight requests
can finish with their previously captured immutable reference. A different
production in-flight policy requires an ADR as required by section 14.2.

All outcomes contain a structured `reason_code`. Validation and fetch failures
never clear or replace the active slot. If Redis is temporarily unavailable, the
fetch adapter reports failure and requests continue capturing the last validated
in-memory Snapshot. The consumer has no Control Plane database dependency and
must never perform a synchronous PostgreSQL fallback.

## Staleness and observability

`Get-RuntimeSnapshotMetrics` emits controlled per-tenant samples containing:

```text
active_config_version
staleness_seconds
propagation_latency_seconds
maximum_staleness_seconds
over_maximum_staleness
on_stale
reason_code
```

Staleness is the non-negative elapsed time since the active Snapshot's
`effective_at`; propagation latency is load time minus notification activation
time. The samples do not use `user_id`, `request_id`, notification ID, or hash as
metric labels.

Maximum staleness defaults to unset (`TBD-016`) and stale behavior defaults to
unset (`TBD-017`). `New-RuntimeSnapshotConsumer` accepts explicit configuration
ports for them and reports whether an explicitly configured threshold has been
crossed, but this task does not invent or execute a fail-open/fail-closed request
decision. That resource-level decision requires configuration or an ADR.

## Failure and rollback guarantees

- Duplicate notification: return `SNAPSHOT_NOTIFICATION_DUPLICATE`; no fetch or
  swap is required.
- Out-of-order `PUBLISH`: return `SNAPSHOT_NOTIFICATION_STALE`; keep active.
- Orphan/half-published notification: return `SNAPSHOT_NOTIFICATION_NOT_CURRENT`;
  keep active.
- Fetch/Redis outage: return `SNAPSHOT_FETCH_FAILED`; keep active.
- Startup/reconnect current read failure: return `SNAPSHOT_CURRENT_READ_FAILED`;
  keep active when one already exists.
- Hash/schema/tenant failure: return the corresponding validation reason; keep
  active.
- `ROLLBACK`: fetch and validate the retained target, then atomically exchange
  the active reference even though its numeric version is older.
- No active Snapshot: return `SNAPSHOT_NOT_LOADED`; no database fallback occurs.

The consumer state is rebuildable from Redis publication state and is never a
system of record.
