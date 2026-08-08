# Retry/Fallback contracts

TASK-M2-006 defines a Data Plane orchestration boundary above the single-attempt
Provider Adapter. A tenant/config-scoped Runtime Snapshot plan explicitly lists
the initial attempt, retries, fallbacks, eligible error kinds, and delay for
every step. There is no global attempt-count, backoff, jitter, or Provider-order
default hidden in runtime code.

The first step must match the Router-selected opaque `provider_id`. A retry keeps
the preceding Provider; a fallback changes it. Only a result classified by the
Provider Adapter as `retryable` can advance, and the next step must explicitly
list the preceding `error_kind`. Success and non-retryable failure stop
immediately. Every plan Provider must be in the opaque post-Policy Router
`eligible_provider_ids` set, preventing fallback from bypassing Policy/Router
filtering. The Provider Adapter itself remains single-attempt.

`retry-fallback-telemetry.v1.schema.json` records the failed Provider IDs,
attempt/retry/fallback counts, per-attempt reason and duration, config/plan
version, fallback usage, and final result. Prompt, response body, endpoint,
Provider model, `secret_ref`, credentials, raw errors, and stack traces are
forbidden. `request_id` and `trace_id` are correlation attributes and must never
be high-cardinality Prometheus labels.

The online Data Plane must not synchronously query Control Plane PostgreSQL.
Plans arrive through the existing versioned Runtime Snapshot publication path.
Usage, Billing, Audit, and Analytics persistence stays asynchronous; the Usage
Event boundary is implemented by `TASK-M2-007` and never blocks this result.

The backend method signature and DI composition stay `TBD-002`/ADR-needed;
`ADR-001` only selects the Gateway language. Public error mapping is
`TBD-008`/`TBD-017`. Production attempt limits, backoff/jitter algorithms,
timeouts, plan values, and SLO thresholds require tenant configuration or ADR
and are not selected by this reference. Retry after partial streaming output is
also an explicit ADR gap; the reference returns
`STREAM_RETRY_POLICY_UNRESOLVED` instead of inventing semantics. Numeric values
in the conformance suite are test fixtures only.

Run the failure-injection suite:

```powershell
pwsh -NoLogo -NoProfile -File ./apps/provider/retry-fallback.conformance.ps1
```

Update the v1 compatibility baseline only with an explicitly reviewed migration
and rollback plan. Runtime rollback means republishing a retained valid Snapshot
plan version; source-only rollback is a Git revert.
