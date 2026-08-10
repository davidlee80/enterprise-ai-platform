# ADR-005: Gateway request pipeline and non-blocking Usage enqueue

- Status: Accepted
- Decision date: 2026-08-10
- Approved by: User direction to implement the repository audit findings
- Affected requirements: `REQ-GEN-001`, `REQ-GEN-004`, `REQ-GEN-005`,
  `REQ-GEN-006`, `REQ-CODE-007`, `REQ-TST-004`, `TASK-M2-002` through
  `TASK-M2-007`
- Resolved item: Gateway application port signatures and the Usage producer
  method signature
- Still unresolved: Identity Provider, Runtime Snapshot transport, Provider
  adapter product/deployment, broker, buffering, retry/DLQ, and `TBD-017`

## Context

The repository had individually executable authentication, Policy, Router,
Provider, Retry/Fallback, and Usage contracts, but the ASP.NET request handler
did not compose them. It returned 503 for every request. The Usage boundary also
required a non-blocking enqueue but deliberately left its application method
signature undecided.

## Decision

`GatewayRequestPipeline.ExecuteAsync(request, cancellationToken)` owns the
online orchestration sequence:

```text
authenticate -> get published snapshot -> policy -> route
  -> bounded Provider attempts -> non-blocking Usage enqueue
```

Infrastructure is accessed only through replaceable Application ports. The
pipeline carries verified tenant and config version through every decision and
never receives a Control Plane repository. Provider request/response bytes are
opaque to the orchestration layer and are never logged.

Usage uses this synchronous attempt-only port:

```csharp
UsageEnqueueResult TryEnqueue(GatewayUsageObservation observation);
```

`TryEnqueue` may write only to an already available in-process buffer. It must
not wait for broker acknowledgement, perform network I/O, or write Usage,
Billing, Audit, or Analytics storage. A throw or unavailable result is converted
to `USAGE_ENQUEUE_UNAVAILABLE` and cannot change a successful Provider response.

Provider invocation remains asynchronous and cancellable. The maximum attempt
count comes from the validated Runtime Snapshot; this ADR selects no production
count, delay, eligibility list, or streaming retry behavior.

## Security and failure behavior

- Missing credentials are denied; configured-but-unavailable adapters fail
  closed with structured reason codes.
- Authenticated tenant, Snapshot tenant, Policy tenant, and Router tenant must
  match before Provider invocation.
- Prompt/response bodies and credentials are absent from logs and Usage events.
- Policy denial and indeterminate decisions cannot reach Router or Provider.
- Provider exhaustion returns the existing 502 status semantic without an
  invented `TBD-008` error body.

## Test and rollback

Executable architecture tests inject fakes and verify authentication denial,
Policy denial, ordered Provider fallback, tenant/config propagation, successful
response delivery, and a thrown Usage enqueue that does not block success.
Default production registrations remain unavailable and fail closed until
reviewed adapters and a validated Runtime Snapshot source replace them.

Rollback is a Git revert and previously verified immutable image digest. A
breaking port change requires a superseding ADR and compatibility tests.
