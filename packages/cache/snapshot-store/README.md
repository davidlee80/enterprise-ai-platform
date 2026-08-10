# Redis Runtime Snapshot Store

This directory implements the `TASK-M1-003` Redis boundary for versioned Runtime
Snapshots. PostgreSQL and the Control Plane remain the system of record. Redis
contains rebuildable publication state only and must never become the unique
source of a business fact.

## Key contract

All keys include an explicit tenant boundary. The braces are Redis Cluster hash
tags, so the immutable version, current pointer, and notification stream for a
tenant share one slot and can be changed by one Lua script:

```text
runtime-snapshot:{tenant_id}:version:<config_version>
runtime-snapshot:{tenant_id}:current
runtime-snapshot:{tenant_id}:notifications
```

The tenant identifier passed to a script must exactly match the tenant embedded
in every key and the Snapshot payload. Braces are not allowed inside a tenant
identifier because they would make the cluster hash tag ambiguous. A global
resource, when explicitly designed later, must use its own reviewed tenant-like
scope rather than omitting the boundary.

Version hashes are immutable. A retry with the same payload and SHA-256
`content_hash` is idempotent; a different payload for an existing version returns
`SNAPSHOT_VERSION_CONFLICT`. There is no `EXPIRE`, deletion, or retention value in
this task. Retention policy is not implied by the store contract.

The current pointer carries the selected payload and publication metadata so a
Data Plane read does not need a second cross-slot lookup. `publish.lua` advances
it using `expected_current_version` compare-and-swap. The script validates all
inputs and key types before its first write, writes an absent immutable version
first, appends the notification, and changes the pointer last. A rejected
publication therefore leaves the old valid pointer effective; an unexpected
pointer write failure can at most leave a rebuildable immutable version and an
orphan notification. The Data Plane confirms the current pointer before swap,
so that orphan cannot activate a partially published candidate.

`rollback.lua` uses the same compare-and-swap rule to select a retained older
version without deleting or overwriting either version. All scripts return JSON
with `ok` and a structured `reason_code`; payloads and credential values are not
included in rejection responses.

## Script interfaces

| Script | Keys | Arguments |
|---|---|---|
| `publish.lua` | version, current, notifications | expected current version, new version, tenant, Snapshot JSON, content hash, effective time, rollback revision, activation time, notification ID |
| `read-current.lua` | current | tenant |
| `read-version.lua` | version | tenant, version |
| `rollback.lua` | target version, current, notifications | expected current version, target version, tenant, activation time, notification ID |

Callers compile and validate
[`runtime-snapshot.v1.schema.json`](../../../docs/contracts/runtime-snapshots/runtime-snapshot.v1.schema.json)
before publication and calculate the SHA-256 hash over the exact JSON bytes.
The store also checks required core fields, tenant/version consistency, and
credential-shaped field names before moving the pointer. Provider entries are
logical identifiers; plaintext Provider credentials are forbidden and future
secret references must use `secret_ref`.

## CP/DP and task boundaries

The Control Plane publishes only after its PostgreSQL transaction and Outbox
event. The Data Plane reads a published Snapshot and must not fall back to a
Control Plane business repository during normal requests. The notification
Stream, consumer fetch/validation, atomic in-memory swap, staleness metrics, and
last-in-memory fallback are implemented by `TASK-M1-004` without adding a
Control Plane database dependency.

Maximum Snapshot staleness has a versioned `TBD-016` configuration contract, but
its production value remains null. Resource-specific fail-open or fail-closed
behavior remains `TBD-017`. This store hard-codes neither and does not define a
production Redis version, topology, durability, authentication, or eviction
policy.

## Test

`snapshot-store.integration.ps1` exercises publish/read, CAS failure, immutable
version conflict, tenant isolation, credential-field rejection, retained-version
reads, and rollback against an isolated Redis service. The PR workflow pins an
exact official Redis image only as a reproducible CI compatibility sample.
