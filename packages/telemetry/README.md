# Telemetry

Reusable metrics, logging, and tracing primitives. Telemetry must carry required
structured context without exposing secrets or using request/user identifiers as
high-cardinality Prometheus labels.

The versioned
[`Retry/Fallback telemetry contract`](../../docs/contracts/retry-fallback/retry-fallback-telemetry.v1.schema.json)
captures Provider attempt latency/error, retry/fallback counts, failed Provider
IDs, config/plan versions, and the final structured reason. Request and trace
IDs remain correlation attributes, not metric labels; Prompt/Response bodies,
endpoints, credentials, raw errors, and stack traces are forbidden.

The [`Usage Event processing contract`](../../docs/contracts/events/usage/usage-processing-result.v1.schema.json)
provides enqueue/publish/consume outcomes and backlog projections. Event,
usage-record, request, trace, and user identifiers are correlation attributes,
not Prometheus labels. Token/cost observations remain body-free and versioned.

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
