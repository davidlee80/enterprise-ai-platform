# Provider

Control Plane provider-registry and capability-management boundary. Provider
credentials must only be referenced through `secret_ref`; plaintext keys do not
belong in this application or its metadata.

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

## Provider Adapter Boundary v1

The versioned [`Provider Adapter contracts`](../../docs/contracts/providers/README.md)
accept only a Router-selected opaque Provider ID and return a normalized,
structured result. Internal endpoint, Provider model, `secret_ref`, and resolved
credential values remain inside adapter infrastructure and never reach upper
layers or result/error payloads.

Adapters are registry-driven. The conformance suite proves native and LiteLLM
mock adapters can be added without modifying Gateway/Router lifecycle code.
LiteLLM is restricted to Provider request/response/stream and error
normalization; platform tenant, authentication, authorization, policy, budget,
routing, audit, and config version remain platform-owned.

Each invocation performs exactly one Provider attempt. Structured retry hints
feed the versioned
[`Retry/Fallback boundary`](../../docs/contracts/retry-fallback/README.md); this
adapter does not independently retry or fallback. Secret Manager selection
remains `TBD-012`, and LiteLLM SDK versus Proxy mode and dependency version
require an ADR.

## Retry/Fallback Boundary v1

TASK-M2-006 consumes an explicit tenant/config-scoped attempt plan and emits a
structured final reason plus per-attempt telemetry. Retries retain the previous
opaque Provider ID; fallbacks change it. Only explicitly eligible, retryable
Provider results advance the plan. No production attempt count, timeout,
backoff, jitter, or public error mapping is hard-coded by the reference suite.
