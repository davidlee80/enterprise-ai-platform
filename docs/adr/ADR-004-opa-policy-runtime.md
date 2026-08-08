# ADR-004: OPA Policy Runtime for the Gateway Data Plane

- Status: Accepted
- Decision date: 2026-08-08
- Approved by: User direction to implement `TBD-004`
- Affected requirements: `REQ-CODE-003`, `REQ-CODE-007`, `REQ-ARCH-002`,
  `TASK-M2-003`, `AC-CODE-001`
- Resolved item: `TBD-004` for the Gateway
- Selected baseline: Open Policy Agent `v1.19.0`, REST Data API v1
- Still unresolved: `TBD-008`, `TBD-017`

## Context

Policy Decision v1 already requires `allow`, structured denial reasons,
obligations, matched policy IDs, policy version, tenant/config scope, and an
`indeterminate` outcome. It deliberately left CEL, OPA, and a custom engine
open. The Data Plane needs an implementation that evaluates locally published
policy data without querying Control Plane PostgreSQL and that remains
replaceable behind a stable application port.

OPA's authoritative REST API accepts `POST /v1/data/{path}` with an `input`
document and returns the selected policy document in `result`. OPA also exposes
health checks and supports versioned bundle activation. The implementation
baseline is the immutable upstream `v1.19.0` release; deployments must pin the
reviewed runtime artifact rather than use `latest`.

## Decision

The Gateway application port is:

```csharp
public interface IPolicyRuntime
{
    ValueTask<PolicyDecision> EvaluateAsync(
        PolicyEvaluationRequest request,
        CancellationToken cancellationToken);
}
```

`OpaPolicyRuntime` implements this port through a loopback-only sidecar at
`http://127.0.0.1:8181/`. It posts the closed Policy Evaluation Request v1 as
`{"input": ...}` to `v1/data/enterprise_ai/gateway/decision` and accepts only a
closed Policy Decision v1 object from `result`.

The application validates principal/request/published-context tenant scope and
config version before calling OPA, then verifies that returned request, trace,
tenant, config, model, and policy versions match the input. Undefined documents,
transport errors, non-success HTTP responses, and invalid result documents
produce structured `indeterminate` decisions. Caller cancellation is propagated.
The boundary never silently converts `indeterminate` to allow or deny, so
resource mapping remains `TBD-017`.

## Compatibility and architecture impact

- Existing language-neutral Policy v1 request/decision schemas remain
  authoritative; the adapter is replaceable through `IPolicyRuntime`.
- OPA is a local Data Plane evaluator. Tenant policy publication/compilation
  remains a Control Plane concern and must arrive through a versioned Runtime
  Snapshot/bundle path, never an online database query.
- The decision path is versioned operational configuration. A new document
  shape requires a new policy contract version or a compatibility adapter.
- OPA management APIs and Compile API are not exposed to Gateway request code.

## Security, tenant, and failure impact

The HTTP endpoint is constrained to an unauthenticated loopback address; it
cannot contain user info, query, or fragment data. Input contains authenticated
identity facts and published policy context, but never policy source, Prompt or
Response bodies, Provider credentials, or internal Provider endpoints. The
adapter does not log request or response bodies.

Only explicit `allow` may proceed to Router. OPA/runtime failures remain
`indeterminate`, preserving the separate resource-specific fail-open/fail-closed
decision in `TBD-017`.

## Test, upgrade, and rollback

Adapter tests use an in-process mock HTTP transport and verify the OPA input
envelope, exact Data API path, allow/obligation decoding, undefined document,
HTTP error, malformed result, tenant pre-check, and cancellation propagation.
Policy schema conformance continues to verify structured decisions and
forbidden disclosure.

OPA upgrades require review of upstream release/security notes, Data API and
bundle compatibility tests, a pinned artifact, canary evidence, and rollback to
the prior reviewed OPA/Gateway image pair. Replacing OPA requires a superseding
ADR and an `IPolicyRuntime` adapter that passes the same Policy v1 contract and
failure tests.

## Primary references

- OPA REST API: <https://www.openpolicyagent.org/docs/rest-api>
- OPA deployment with Docker: <https://www.openpolicyagent.org/docs/deploy/docker>
- OPA bundle management: <https://www.openpolicyagent.org/docs/management-bundles>
- OPA `v1.19.0` release: <https://github.com/open-policy-agent/opa/releases/tag/v1.19.0>
