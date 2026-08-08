# ADR-001: Gateway .NET Linux runtime

- Status: Accepted
- Decision date: 2026-08-08
- Approved by: User direction in the implementation session
- Affected requirements: `REQ-REP-001`, `REQ-BLD-001` through
  `REQ-BLD-009`, `TASK-M3-001`, `AC-BLD-001`
- Resolved item: `TBD-001`
- Still unresolved: `TBD-003`, `TBD-004`, `TBD-008`, `TBD-009`,
  `TBD-012`, `TBD-013`, `TBD-016`, `TBD-017`, `TBD-018`, `TBD-019`

## Context

The Gateway needs a real application artifact before its production Linux
container, health endpoints, dependency lock, and runtime evidence can be
implemented. The requirements did not originally select a backend language or
Web Framework, so the image boundary remained blocked by `TBD-001`.

The Gateway is a Data Plane process. It must support streaming HTTP requests,
structured failures, atomic Runtime Snapshot replacement, Provider-neutral
adapters, and OpenTelemetry-compatible logs/metrics/traces without querying the
Control Plane PostgreSQL database on the online request path.

## Decision

The Gateway runtime uses:

| Concern | Decision |
|---|---|
| Backend language | C# |
| Runtime baseline | .NET 10 LTS |
| Web Framework | ASP.NET Core Minimal APIs |
| HTTP server | Kestrel |
| Package manager | NuGet through the `dotnet` CLI |
| Dependency lock | `packages.lock.json` with `dotnet restore --locked-mode` |
| SDK lock | repository `global.json` |
| Production platform | Linux containers on Kubernetes |

The initial reproducible baseline is .NET SDK `10.0.302` and ASP.NET Core
runtime `10.0.10`. Security patch updates remain normal reviewed dependency
changes within the .NET 10 LTS line; this ADR does not authorize floating build
inputs.

The runtime uses only the ASP.NET Core shared framework in its first increment.
It does not introduce a third-party NuGet dependency. Gateway DDD projects and
dependency injection are subsequently resolved by ADR-002.

## Compatibility and architecture impact

- The existing OpenAPI, Authentication, Policy, Router, Provider,
  Retry/Fallback, and Usage contracts remain authoritative.
- Selecting a runtime does not resolve `TBD-003` Router method signatures,
  `TBD-004` Policy Runtime, `TBD-008` public Error Schema, or `TBD-012` Secret
  Manager.
- Until production implementations of those boundaries are registered, the
  process remains live but reports `RUNTIME_SNAPSHOT_UNAVAILABLE` from
  `/readyz`; Kubernetes must not route normal requests to it.
- `/v1/chat/completions` does not fabricate a success path. While the runtime
  pipeline is unavailable it returns HTTP 503 without inventing the
  `TBD-008` public error body and emits a structured internal reason code.
- No request path reads Control Plane PostgreSQL or synchronously persists
  Usage, Billing, Audit, or Analytics data.

## Security and tenant impact

- The runtime never logs Authorization values, request bodies, Provider
  endpoints, `secret_ref` values, or resolved credentials.
- Tenant identity will only come from the verified Authentication principal;
  the bootstrap runtime does not infer it from request input.
- Production images use a numeric non-root UID, read-only-compatible paths,
  digest-pinned Linux base images, and no credential-shaped build arguments.

## Rollback and replacement

Source changes roll back by Git revert. A deployed runtime rolls back by
selecting a previously verified immutable image digest; it must not rebuild a
mutable historical tag. Replacing C# or ASP.NET Core requires a superseding ADR,
contract-equivalence tests, image evidence, and a compatible rollout plan.
