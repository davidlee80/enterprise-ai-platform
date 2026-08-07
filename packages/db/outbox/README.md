# Transactional Outbox boundary

`TASK-M1-002` implements the PostgreSQL persistence and publisher coordination
boundary without selecting a backend language, Kafka SDK, topic topology, or
production retry thresholds.

## Transactional write

The application opens one PostgreSQL transaction, performs its reviewed business
state change, and calls `enqueue_outbox_event` before commit. If either write
fails, both roll back. The non-executable
[`transaction.sql.example`](transaction.sql.example) shows the boundary without
inventing a business-table schema.

The caller supplies `event_id`; the primary key prevents two committed rows with
the same identifier. The event envelope carries the fields required by
`REQ-GEN-011`. Tenant-scoped events carry `tenant_id`; `NULL` is reserved for
reviewed global events and must not be used to bypass tenant authorization.

## Asynchronous publisher

An independently deployed worker follows this state flow:

```text
claim_outbox_events(worker, lease, limit, now, lease_until)
  -> publish the returned versioned envelope to the configured broker
  -> mark_outbox_event_published(event_id, lease, published_at)
     OR
     release_outbox_event(event_id, lease, available_at, reason_code)
```

Claims use `FOR UPDATE SKIP LOCKED` and an expiring lease. Publishing happens
outside the business transaction. A crash after broker acceptance but before
acknowledgement causes redelivery, so delivery is at-least-once and every
consumer must deduplicate by `event_id` or a reviewed business idempotency key.
Event backlog never becomes a prerequisite for completing the online model
request.

Retry delay, maximum attempts, DLQ behavior, broker product, topic names,
partition keys, and publisher polling/notification strategy are configuration or
ADR inputs. No production value is hard-coded by this task.

All Outbox functions revoke default execution from PostgreSQL `PUBLIC`. Runtime
database roles and least-privilege grants require a reviewed IAM/database ADR;
this migration does not guess production role names.

## Failure and observability contract

- Failed publish attempts call `release_outbox_event` with a structured,
  non-secret `reason_code` and a caller-calculated next `available_at`.
- `attempt_count`, lease timestamps, `published_at`, and `last_reason_code` are
  available to metrics/logging without recording Prompt/Response bodies.
- Logs must carry event ID, event type, schema version, tenant ID where present,
  producer, attempt count, and reason code. Payload logging is disabled by
  default.
- Payloads must not contain Provider credentials; use `secret_ref` where an
  indirect reference is part of a reviewed event.

## Rollback

The migration is additive. Application rollback stops the publisher and returns
to a compatible version while retaining unpublished rows. Removing the table or
functions is a later contract migration only after backlog drainage, compatibility
review, and an approved recovery plan.
