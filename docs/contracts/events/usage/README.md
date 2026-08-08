# Usage Event contracts

TASK-M2-007 publishes `UsageObserved` only through a non-blocking asynchronous
boundary after the online request has reached a final result. The request path
constructs the versioned event and performs `try_enqueue`; it never waits for a
broker acknowledgement, Usage/Billing/Audit/Analytics SQL write, aggregation,
or downstream retry. Enqueue rejection is visible through a structured reason
but does not revoke or delay the already completed model response.

The event extends Event Envelope v1 and carries tenant/request/trace/config
context, tenant-visible model alias, opaque final Provider ID, final reason,
retry/fallback counts, timestamps, token observation, and an optional
versioned cost calculation. It contains no Prompt/Response body, Provider model,
endpoint, credential, `secret_ref`, raw error, or stack trace. `UsageObserved`
is an observation for asynchronous processing, not a final invoice fact.

At-least-once delivery is expected. Billing consumers must deduplicate by
`event_id` and by the tenant-scoped `usage_record_id` business key; duplicate
delivery never changes the released online response. Event backlog is isolated
from Gateway request processing. Reuse of either idempotency key with conflicting
tenant or payload content is rejected with a structured conflict reason rather
than silently treated as a duplicate.

Consumer processing failures return an explicit `next_action` of `retry` or
`dead_letter`. The interface supports both actions, while retry schedule,
maximum attempts, and DLQ destination remain configuration/ADR inputs. Failed
processing does not commit the event or business idempotency key.

The Data Plane does not synchronously insert into the PostgreSQL Outbox. The
M1-002 transactional Outbox remains the correct boundary when a database fact
and event must commit atomically; request completion has no synchronous business
database write to pair with it. Production broker/buffer durability and failure
recovery still require an explicit ADR.

The Gateway language is selected by `ADR-001`; producer interface and DI remain
`TBD-002`/ADR-needed. Broker, topic, partition key, producer buffer durability,
overflow handling, publisher
retry/DLQ, Usage aggregation table/buckets/retention, pricing precision,
currency policy, and cost authority are intentionally unresolved. The contract
does not create the pending `usage` table or select Kafka over an equivalent
event mechanism.

Run the asynchronous pipeline and duplicate-delivery conformance suite:

```powershell
pwsh -NoLogo -NoProfile -File ./apps/billing/usage-event.conformance.ps1
```

Schema rollback retains Usage Event v1 for replay and compatible consumers.
Source-only rollback is a Git revert; consumer data rollback/repair remains part
of the future reviewed Usage storage design.
