# Router

Routing configuration and compilation boundary. Runtime routing must remain
extensible and produce structured decisions without leaking provider-specific
credentials to upper layers.

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

## Router Plugin Boundary v1

The versioned [`Router contracts`](../../docs/contracts/router/README.md) define
tenant/config-scoped requests, an ordered plugin registry, structured plugin
results, and a Route Decision. A `route_strategy` selects registry composition;
the core lifecycle contains no strategy-specific dispatch chain. Adding a new
plugin changes registration/composition data rather than the request lifecycle.

Only a Policy Decision `allow` enters routing. Plugins see opaque Provider IDs
and non-secret region/priority/weight/enabled metadata. They never receive
Provider endpoints, `secret_ref`, plaintext keys, or credentials. Only a
`selected` result may proceed to the pending `TASK-M2-005` Provider Adapter.
That adapter is now versioned at
[`provider-adapter-boundary.v1.json`](../../docs/contracts/providers/provider-adapter-boundary.v1.json).

The executable conformance suite uses mock plugins and does not select the
production method signature (`TBD-003`), route algorithm, weight/observation
semantics (`TBD-014`), backend language, or DI framework.
