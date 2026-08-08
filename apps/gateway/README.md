# Gateway

Data Plane API entrypoint and request lifecycle boundary. It consumes published
runtime snapshots and must not synchronously query Control Plane business
repositories on the normal request path.

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

## API contract binding

The language-neutral
[`createChatCompletion` binding](contracts/chat-completions.binding.v1.json)
maps `POST /v1/chat/completions` to the authoritative OpenAPI request, response,
and stream schemas. `ADR-001` implements its bootstrap handler with C#/.NET 10,
ASP.NET Core Minimal APIs, Kestrel, and locked NuGet restore on Linux. Until the
remaining auth/policy/router composition decisions are implemented, the route
fails closed with HTTP 503 and no invented `TBD-008` public error body.

From a Linux repository checkout with .NET SDK 10.0.302:

```bash
dotnet restore apps/gateway/src/EnterpriseAiPlatform.Gateway/EnterpriseAiPlatform.Gateway.csproj --locked-mode
ASPNETCORE_URLS=http://0.0.0.0:8080 dotnet run --project apps/gateway/src/EnterpriseAiPlatform.Gateway/EnterpriseAiPlatform.Gateway.csproj --configuration Release --no-restore
```

`/healthz` returns 200 once the process is live. `/readyz` deliberately returns
503 until a validated Runtime Snapshot and the remaining runtime boundaries are
composed; the bootstrap process must not receive normal model traffic.

## DDD and dependency injection

[`ADR-002`](../../docs/adr/ADR-002-gateway-ddd-dependency-injection.md)
defines compile-time `Domain`, `Application`, `Infrastructure`, and `Api/Host`
projects. Dependencies point inward; Domain is framework-free and the ASP.NET
Host is the only composition root. The Gateway uses the built-in
`Microsoft.Extensions.DependencyInjection` container with replaceable `TryAdd`
registrations. This resolves composition only: plugin/adapter method signatures
and their production implementations remain separately reviewed boundaries.

| Project | Responsibility |
|---|---|
| `EnterpriseAiPlatform.Gateway.Domain` | Framework-free runtime concepts and invariants |
| `EnterpriseAiPlatform.Gateway.Application` | Use cases and infrastructure ports |
| `EnterpriseAiPlatform.Gateway.Infrastructure` | Replaceable port adapters and DI registrations |
| `EnterpriseAiPlatform.Gateway` | ASP.NET Api/Host and the single composition root |

The binding now requires an `authenticated` result from
[`Authentication Boundary v1`](../../packages/auth/contracts/authentication-boundary.v1.json)
before entering the request pipeline. Verified `tenant_id` comes from the
authentication principal; resource/model authorization remains a separate
[`TASK-M2-003` Policy Decision](../../docs/contracts/policy-decisions/policy-boundary.v1.json).
Only an `allow` result proceeds toward routing, and all obligations remain
attached for downstream enforcement. Neither the Gateway nor shared auth/policy
components may synchronously query Control Plane PostgreSQL on the online
request path.

An allowed Policy Decision now enters the versioned
[`Router Plugin Boundary`](../../docs/contracts/router/router-boundary.v1.json).
The Gateway requires a structured `selected` Route Decision before invoking the
pending `TASK-M2-005` Provider Adapter; it never resolves Provider endpoints or
credentials inside the Router boundary.

The Provider Adapter boundary is now versioned and may dispatch to a registered
native or LiteLLM runtime adapter. Gateway-visible results retain only the model
alias and opaque Provider/adapter IDs. Runtime endpoint, Provider model,
`secret_ref`, resolved credential, and raw Provider error stay internal.

Provider results enter the versioned
[`Retry/Fallback Boundary`](../../docs/contracts/retry-fallback/retry-fallback-boundary.v1.json).
Its Runtime Snapshot plan explicitly controls every retry/fallback attempt and
delay. Gateway public-error mapping remains `TBD-008`/`TBD-017`; Usage event
publication uses the asynchronous
[`TASK-M2-007` boundary](../../docs/contracts/events/usage/README.md).
