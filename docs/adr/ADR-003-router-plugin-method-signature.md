# ADR-003: Gateway Router Plugin method signature

- Status: Accepted
- Decision date: 2026-08-08
- Approved by: User direction to implement `TBD-003`
- Affected requirements: `REQ-CODE-002`, `REQ-CODE-007`, `TASK-M2-004`,
  `AC-CODE-001`
- Resolved item: `TBD-003` for the Gateway
- Still unresolved: `TBD-014`, `TBD-017`

## Context

Router v1 already defines a tenant/config-scoped registry, ordered plugin
pipelines, structured plugin results, and the rule that adding a strategy must
not add a strategy-specific branch to the core request lifecycle. ADR-001 and
ADR-002 subsequently selected C#/.NET and the built-in DI container, so the
remaining gap is the smallest production method contract that preserves those
language-neutral schemas.

## Decision

Gateway routing plugins implement:

```csharp
public interface IRouterPlugin
{
    string PluginId { get; }
    ContractVersion PluginVersion { get; }

    ValueTask<RouterPluginResult> RouteAsync(
        RouterPluginContext context,
        CancellationToken cancellationToken);
}
```

`RouterPluginContext` is an immutable snapshot of the request and the currently
ordered, opaque Provider candidates. `RouterPluginResult` is the typed form of
the existing closed v1 result schema. Plugin identity/version are checked
against the tenant/config-scoped registry before a result is accepted.

The application pipeline resolves `route_strategy` through registry data and
then composes registered `IRouterPlugin` instances. It contains no strategy-
specific dispatch chain. Cancellation is propagated. A thrown plugin exception,
missing plugin, version mismatch, or invalid candidate result becomes a
structured Router `indeterminate` result; this boundary does not map that result
to a public resource response.

## Compatibility and architecture impact

- The published Router v1 JSON schemas remain unchanged and authoritative at
  process boundaries.
- A new strategy supplies an `IRouterPlugin` implementation and registry entry;
  it does not modify the request lifecycle.
- The interface lives in Application, typed values live in the framework-free
  Domain project, and concrete plugins are composed through ADR-002 DI.
- The method makes no selection-algorithm, grey-weight, or observation-window
  decision. Those semantics remain `TBD-014`.

## Security, tenant, and failure impact

Plugins receive Provider IDs and non-secret routing metadata only. They do not
receive endpoints, `secret_ref`, plaintext keys, credentials, or a Control
Plane database handle. Registry/request tenant and config versions must match
before invocation. Cancellation remains observable and is never converted into
a successful route.

## Test and rollback

Runtime conformance uses replaceable fake plugins to prove signature shape,
ordered composition, dynamic registration, invalid-result rejection, trace
generation, and cancellation propagation. Existing schema conformance continues
to cover tenant/config mismatch and disclosure guards.

Rollback is a Git revert while no external plugin assembly targets this
interface. A later signature change requires a superseding ADR, a new interface
version or compatibility adapter, registry migration evidence, and rollback to
a previously verified Gateway image digest.
