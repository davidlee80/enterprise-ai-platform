# Runtime Snapshot schemas

[`runtime-snapshot.v1.schema.json`](runtime-snapshot.v1.schema.json) is the first
machine-readable Runtime Snapshot contract. It preserves the core semantics from
`REQ-GEN-003` and `REQ-GEN-009`: configuration version, tenant, model alias,
policy identifiers, route strategy, and candidate Providers. Additive fields are
allowed so a later version can be introduced deliberately when compatibility
requires it.

`TASK-M2-006` adds the optional `retry_fallback_plan` reference as a compatible
v1 extension. When present, its tenant and config version must match the
Snapshot and every attempt/delay is explicit. Older retained Snapshots remain
valid; rollback may therefore select a version without Retry/Fallback or a prior
plan version without rewriting stored payloads.

[`snapshot-notification.v1.schema.json`](snapshot-notification.v1.schema.json)
is the compact tenant/version notification consumed by the Data Plane. It carries
the expected content hash and publication transition but never embeds the full
Snapshot or credentials. Duplicate notifications are valid delivery behavior;
consumers deduplicate by tenant, version, and content hash.

The Snapshot payload is compact runtime configuration, not a Control Plane
record. Publication metadata (`content_hash`, `effective_at`, activation time,
and rollback information) is stored beside the payload by the versioned Redis
Snapshot Store. PostgreSQL remains the system of record; Redis is a rebuildable
publication and acceleration layer.

Snapshot payloads must never embed plaintext Provider credentials. Provider
entries are logical identifiers, and any future secret-bearing extension must
use an indirect `secret_ref`. The store rejects credential-shaped field names
before changing the current pointer.

`TASK-M1-003` owns immutable version storage, reads, compare-and-swap publication,
the current pointer, and rollback to a retained version. `TASK-M1-004` adds the
version notification contract and stream, Data Plane validation/fetch state
machine, atomic in-memory replacement, last-memory failure behavior, and
staleness metrics. Any failed publication or candidate validation leaves the
last valid snapshot selected.

[`runtime-staleness-policy.v1.schema.json`](runtime-staleness-policy.v1.schema.json)
provides the versioned `TBD-016` configuration entry point. When included as the
optional `staleness_policy`, its tenant and `config_version` must match the
Snapshot. The production maximum remains null; only positive seconds are valid
after review. The executable boundary and compatibility baseline preserve raw
measurement, rollback, and telemetry-label safety.

Threshold-exceeded fail-open/fail-closed behavior remains `TBD-017`. Measuring
that a threshold was crossed does not itself change request availability. No
retention, expiry, or Redis outage policy is set by this contract.
