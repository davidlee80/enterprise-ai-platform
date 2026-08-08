# ADR-002: Gateway DDD projects and dependency injection

- Status: Accepted
- Decision date: 2026-08-08
- Approved by: User direction to implement `TBD-002`
- Affected requirements: `REQ-CODE-001`, `REQ-CODE-007`, `TASK-CODE-001`,
  `AC-CODE-001`
- Resolved item: `TBD-002` for the Gateway
- Still unresolved: `TBD-003`, `TBD-004`, `TBD-008`, `TBD-012`, `TBD-014`,
  `TBD-016`, `TBD-017`

## Context

ADR-001 selected C# and ASP.NET Core for the Linux Gateway, but deliberately
left the concrete DDD directory convention and dependency-injection framework
unresolved. The bootstrap executable consequently had no compile-time layer
boundaries or composition root through which the existing Authentication,
Policy, Router, Provider, Retry/Fallback, Usage, and Runtime Snapshot contracts
could later be registered.

The decision must make dependencies and replacement tests explicit without
inventing the method signatures or production implementations that remain
separate TBD/ADR items.

## Decision

The Gateway uses these projects and dependency direction:

```text
Api/Host -------> Application -------> Domain
    |                  ^                  ^
    +-----> Infrastructure --------------+
```

- `Domain` owns framework-free runtime concepts and invariants.
- `Application` owns use cases and ports and references only `Domain`.
- `Infrastructure` implements Application ports and may use approved runtime
  framework integrations. It references `Application` and `Domain`.
- `Api/Host` owns ASP.NET endpoint mapping, logging, process health, and the
  single composition root. It references `Application` and `Infrastructure`.

The Gateway uses the .NET built-in `Microsoft.Extensions.DependencyInjection`
container. Registration extensions live in Infrastructure; Host performs the
final composition. Default implementations use `TryAdd` so conformance tests
and later approved adapters can replace ports without service-location or
strategy branches in the request lifecycle.

This is a Gateway decision. It does not impose a directory or DI standard on
other applications that do not yet have an approved runtime.

## Dependency and compatibility constraints

- `Domain` has no project, package, or framework reference.
- `Application` must not reference `Infrastructure` or `Api/Host`.
- `Infrastructure` must not reference `Api/Host`.
- Domain and Application code must not resolve services from `IServiceProvider`.
- This ADR selects composition only. Router Plugin methods remain `TBD-003`,
  Policy Runtime remains `TBD-004`, and Provider/Retry/Usage method signatures
  remain separate ADR-needed items.
- Existing versioned schemas remain authoritative and unchanged.

## Security, tenant, and failure impact

- The default Runtime Snapshot availability adapter is fail-closed and never
  queries Control Plane PostgreSQL.
- Tenant identity will continue to enter through the verified Authentication
  principal; DI registration does not create ambient or global tenant state.
- Service registration accepts no credential values and does not log resolved
  services, request bodies, `secret_ref`, or Provider configuration.
- Missing production adapters leave `/readyz` unavailable and the model route
  at HTTP 503.

## Test and rollback

Architecture conformance checks the project-reference graph, validates the
container at build time, resolves each required service exactly once, and
proves a fake port can replace the default implementation. Runtime conformance
continues to verify health, readiness, failure response, and secret safety.

Rollback is a Git revert of this ADR and its project split while no production
adapter depends on it. After adapters are implemented, replacement requires a
superseding ADR, equivalent contract tests, and a compatible deployment
rollback using a previously verified image digest.
