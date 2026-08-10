# OpenAPI contracts

[`openapi.yaml`](openapi.yaml) is the authoritative OpenAPI 3.1 contract for the
public `/v1` baseline. The file uses JSON syntax, which is also valid YAML 1.2,
so the repository can parse and validate it without selecting a package manager
or adding an unpinned parser dependency.

`POST /v1/chat/completions` exposes the minimal stable OpenAI-compatible core:
`model` and `messages` in the request, plus `id`, `object`, `created`, `model`,
and `choices` in the response. Optional/additive fields remain allowed. The
baseline also describes `text/event-stream` chunks without requiring streaming
for every request. This shape follows the official
[OpenAI Chat Completions API reference](https://developers.openai.com/api/reference/resources/chat).

## Authentication boundary

The operation expresses both `BearerAuth` and `ApiKeyAuth` capabilities. At this
bootstrap boundary both are bearer-class credentials, which preserves an
OpenAI-compatible Authorization flow without inventing a custom header. The
concrete authentication implementation, Identity Provider, and any separate API
key Header remain `REQ-API-003` / ADR decisions. TASK-M2-002 provides the
language-neutral
[`Authentication Boundary v1`](../../../packages/auth/contracts/authentication-boundary.v1.json)
for normalized credentials and structured decisions. The contract carries
`x-authentication-contract` and `x-authentication-tbd` markers so the executable
boundary cannot be mistaken for a final Header or Identity Provider design.

## Error boundary

The required HTTP semantics are published for `200`, `400`, `401`, `403`, `429`,
and `502`. Error responses deliberately contain descriptions only. The complete
JSON error body, internal error-code enumeration, and `402` semantics remain
`TBD-008`; this task does not invent them. Descriptions expose no Provider key,
internal endpoint, policy source, or stack trace.

The document-level `x-http-error-semantics-contract` extension links the
versioned [`HTTP error status boundary`](../errors/README.md). Its compatibility
baseline protects the required `400/401/403/429/502` meanings. Public body
schema/media type, field names, public-code mapping, correlation fields, and
`402` semantics remain null under `TBD-008`.

## Management idempotency extension point

The document-level `x-admin-idempotency-contract` extension links the versioned
[`Admin write idempotency contract`](../idempotency/README.md). Management
routes are not fabricated in the Data Plane `/v1` baseline, but every future
create, patch, publish, and rollback operation must bind to that contract.
Header name, TTL, storage, replay/conflict mapping, and store-failure behavior
remain null and traceable to `TBD-005`; the extension is not a production
default.

## Management pagination review boundary

The document-level `x-admin-pagination-contract` extension links the versioned
[`Admin list pagination contract`](../pagination/README.md). It preserves cursor
and offset as review candidates without selecting either one or publishing HTTP
query parameter names. Strategy, page-size policy, cursor encoding/expiry, and
consistency behavior remain null and traceable to `TBD-006` until API design
review. Management list paths will be added only by their owning API task.

## SDK generation pipeline

The document-level `x-sdk-generation-contract` extension links the versioned
[`SDK generation boundary`](../../../packages/sdk/README.md). The authoritative
OpenAPI document is validated, compatibility-checked, and hashed as pipeline
input. Language set, generator/version, output layout, and package registry
remain null under `TBD-007`; generation, generated-client tests, and publishing
stay disabled until review.

## Deprecation workflow

The document-level `x-deprecation-contract` extension links the versioned
[`Deprecation boundary`](../deprecation/README.md). No operation in this baseline
is currently marked deprecated. A future API deprecation requires an explicit
reviewed policy, start and end timestamps, migration/replacement evidence, and
retention through the configured window.

Window duration and syntax, scheduling rules, notification channels, post-window
enforcement, and exception behavior remain null under `TBD-015`. A breaking
change still requires a new API version and migration path; the deprecation
workflow does not weaken `/v1` compatibility.

## Validation and compatibility

Run from the repository root:

```powershell
pwsh -NoLogo -NoProfile -File ./scripts/openapi.ps1 validate
pwsh -NoLogo -NoProfile -File ./scripts/openapi.ps1 compatibility
pwsh -NoLogo -NoProfile -File ./packages/sdk/generate.ps1 plan
```

Validation parses the contract, resolves all local references, checks the
required path/security/status/schema semantics, verifies positive and negative
fixtures, and checks the machine-readable Gateway handler binding.

[`compatibility-baseline.v1.json`](compatibility-baseline.v1.json) records the
operation, status/media/auth semantics, and every currently published schema
property signature that cannot be silently removed or changed. Update that
baseline only with an explicitly reviewed breaking-change and migration plan;
ordinary additive fields do not require a baseline change.

The SDK entrypoint validates and hashes the authoritative contract for a future
generator. SDK language and generator selection remain `TBD-007`, so it emits a
structured plan rather than choosing a language or producing misleading SDK
artifacts.

The handler binding is stored at
[`apps/gateway/contracts/chat-completions.binding.v1.json`](../../../apps/gateway/contracts/chat-completions.binding.v1.json).
`ADR-001` maps it to the .NET 10 bootstrap handler and `ADR-002` supplies its
DDD/DI composition root; M2-001 remains the authoritative language-neutral API
contract.
