# Policy Decision schemas

Canonical location for the versioned Policy Evaluation and Policy Decision
contracts implemented by `TASK-M2-003`:

- [`policy-evaluation-request.v1.schema.json`](policy-evaluation-request.v1.schema.json)
  carries authenticated principal, request/trace, tenant, config, model, region,
  estimated-cost, and published policy-context inputs.
- [`policy-decision.v1.schema.json`](policy-decision.v1.schema.json) returns
  `allow`, a structured denial reason through `deny_reason`/`reason_code`, typed
  obligations, matched policy identifiers, and policy version.
- [`policy-boundary.v1.json`](policy-boundary.v1.json) defines pipeline and
  failure invariants and binds the Gateway adapter to OPA Data API v1 through
  `ADR-004`.
- [`policy-compatibility-baseline.v1.json`](policy-compatibility-baseline.v1.json)
  records the v1 fields, outcomes, obligation kinds, and router guard that
  cannot be silently removed or changed.

The decision can express `allow`, `deny`, or `indeterminate`. An indeterminate
result is never silently converted inside this interface; the resource-specific
mapping remains `TBD-017`. Only `allow` may enter the `TASK-M2-004` router
boundary, now versioned at
[`router-boundary.v1.json`](../router/router-boundary.v1.json).

Typed obligations cover `mask`, `redact`, `force_region`,
`disable_body_logging`, and `limit_max_tokens`. They are downstream
requirements, not authorization by themselves. Consumers must apply all
obligations before or during the affected operation.

Policy inputs come from the authenticated principal and locally available,
published policy context for the same tenant and `config_version`. The Data
Plane must not synchronously query Control Plane PostgreSQL or filter a
cross-tenant result set during evaluation. Audit/Usage/Billing/Analytics
persistence remains asynchronous and cannot block the decision.

Run the executable policy mock/conformance suite from the repository root:

```powershell
pwsh -NoLogo -NoProfile -File ./apps/policy/policy-decision.conformance.ps1
```

`ADR-004` selects Open Policy Agent `v1.19.0` behind the replaceable
`IPolicyRuntime` port. The Gateway posts `{ "input": ... }` to the loopback
Data API document `v1/data/enterprise_ai/gateway/decision` and accepts only a
closed Policy Decision v1 object in `result`. Runtime/bundle upgrades remain
pinned and reviewed; production tenant policy content and evaluation order are
not hard-coded by the adapter. Decisions contain no policy source, Prompt or
Response body, Provider credential, internal endpoint, or subject identity.
Complete public error bodies remain `TBD-008`, and indeterminate resource
mapping remains `TBD-017`.

Changing the compatibility baseline requires an explicitly reviewed breaking-
change and migration plan. Ordinary additive reason codes or optional contract
extensions require a new versioned schema field where the closed v1 envelope
would otherwise reject them.
