# Provider Adapter contracts

TASK-M2-005 defines a Provider-neutral invocation boundary, structured result,
adapter registry, internal runtime configuration, and LiteLLM runtime role.
Upper layers pass only a selected opaque `provider_id`; endpoint, Provider model,
`secret_ref`, and resolved credentials remain inside adapter infrastructure.

`provider-invocation-request.v1.schema.json` carries the OpenAI-compatible chat
core without Provider-specific fields. `provider-invocation-result.v1.schema.json`
normalizes success and error classification without exposing raw errors. A
single invocation performs one Provider attempt. The versioned
[`Retry/Fallback boundary`](../retry-fallback/README.md) owns multi-attempt
orchestration; Provider adapters never retry independently.

`provider-runtime-config.v1.schema.json` is internal published Data Plane
configuration. Its endpoint, Provider model, and `secret_ref` fields are
write-only and must never appear in upper-layer inputs, results, logs, metrics,
traces, or public errors. The Secret Resolver implementation and product remain
`TBD-012`. The online Data Plane must not synchronously query Control Plane PostgreSQL;
it consumes only the published, versioned runtime binding.

LiteLLM is an optional registered runtime adapter for request/response/stream and
error normalization. It is not the fact source for tenant, authentication,
authorization, budget, policy, routing, audit, or config version. SDK versus
Proxy deployment and dependency version remain explicit TBD/ADR items.
Retry/Fallback stays platform-owned outside LiteLLM. This boundary follows the official
[LiteLLM documentation](https://docs.litellm.ai/) for OpenAI-format input/output.

Run the Provider Mock conformance suite:

```powershell
powershell -NoProfile -File .\apps\provider\provider-adapter.conformance.ps1
```

Adding an adapter is a registry/runtime-binding change and does not change the
Gateway, Router, or core invocation lifecycle. Update the v1 compatibility
baseline only with an explicitly reviewed breaking-change and migration plan.
