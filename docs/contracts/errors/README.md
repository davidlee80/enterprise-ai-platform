# Public HTTP error semantics

This directory implements the `TBD-008` development handling: publish only the
HTTP status semantics explicitly required by `REQ-API-004`, without inventing a
complete public Error JSON Schema.

The versioned boundary and compatibility baseline require:

- `400` — Invalid request;
- `401` — Authentication failed;
- `403` — Policy or model denied;
- `429` — Rate or quota exceeded;
- `502` — Provider failure after fallback exhaustion.

Each OpenAPI response deliberately has a description and no `content` object.
The public body schema/media type, field names, public error-code mapping,
correlation fields, and `402` semantics remain null and marked `TBD-008`.
Structured internal reason codes remain mandatory; the absence of a public body
does not permit free-text-only decisions.

Public errors must not expose Provider credentials, `secret_ref`, internal
endpoints, policy source, stack traces, raw Provider errors, Prompt/Response
bodies, or another tenant's data. The runtime must normalize internal failures
before an eventual reviewed public mapping is applied.

Run from the repository root:

```powershell
pwsh -NoLogo -NoProfile -File ./docs/contracts/errors/http-error-semantics.conformance.ps1
pwsh -NoLogo -NoProfile -File ./scripts/task.ps1 test-tbd-008
```

Removing a required status or changing its meaning is a breaking change. A
future body schema requires an API ADR, explicit contract version, compatibility
test, client migration, and rollback plan. Rollback retains the previous
OpenAPI/status-semantics version rather than attaching a new body to old `/v1`.
