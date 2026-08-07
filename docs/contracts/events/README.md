# Event schemas

Canonical location for versioned asynchronous event schemas and compatibility
fixtures. `TASK-M1-002` publishes the first contract:

- [`event-envelope.v1.schema.json`](event-envelope.v1.schema.json)
- [`UsageObserved v1 and asynchronous processing boundary`](usage/README.md)

Every published envelope preserves the minimum semantics in `REQ-GEN-011` and
`REQ-EVT-001` through `REQ-EVT-003`, including explicit `schema_version` and the
`event_id` idempotency key. `request_id` and `trace_id` are optional correlation
fields. `tenant_id` is required as a field; its value may be null only for a
reviewed global event, never as a tenant-isolation bypass.

Consumers must tolerate duplicate delivery, and event backlog must not block the
online model request path. Payloads must not contain plaintext Provider secrets.
Event types, payload schemas, topic names, retention periods, partition keys, and
the broker/serialization product are defined by their owning tasks or ADRs; this
envelope does not select them.

`TASK-M2-007` specializes the envelope for a tenant-scoped Usage observation.
Its producer performs only non-blocking enqueue on the request path; publisher
and idempotent Billing consumer stages remain asynchronous. Payload and
processing results are secret/body-free, and high-cardinality identifiers are
correlation attributes rather than metric labels.

Changes to envelope field meaning require a new explicit schema version and
compatibility evidence. Rollback keeps the prior schema available for replay and
consumers until its reviewed deprecation window closes.
