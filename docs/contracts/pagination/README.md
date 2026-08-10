# Admin list pagination contract

This directory implements the `TBD-006` development handling for
`REQ-API-006`: it creates an API-design-review boundary without choosing cursor
or offset as the production standard.

The query and result schemas describe normalized cursor and offset candidates so
both can be evaluated by contract tests. They do not define HTTP query parameter
names. `pagination-boundary.v1.json` keeps the selected strategy, transport
binding, page-size defaults/limits, cursor codec/expiry, and consistency behavior
null and explicitly marked `TBD-006`.

All list implementations must filter and authorize the tenant scope before
pagination. Positions cannot be reused across tenant scopes, response context
retains `config_version`, and failures use structured reason codes. Cursor
values must not expose credentials, internal endpoints, or other tenants' data;
request IDs, user IDs, and cursor values are forbidden as Prometheus labels.

The versioned policy schema carries revision, effective time, rollback revision,
and content hash. A policy cannot be activated until API design review selects a
strategy and fills every applicable transport and behavior field. Rollback
publishes the recorded prior revision rather than editing runtime state.

The conformance suite uses deterministic in-memory fixtures for both candidate
strategies. This proves candidate shapes, tenant filtering, page continuity,
structured results, and compatibility without endorsing either candidate or a
production cursor encoding.

Run from the repository root:

```powershell
pwsh -NoLogo -NoProfile -File ./docs/contracts/pagination/pagination-boundary.conformance.ps1
pwsh -NoLogo -NoProfile -File ./scripts/task.ps1 test-tbd-006
```

A future API review must publish its ADR, update the OpenAPI management-list
operations, preserve or version this compatibility baseline, and provide a
migration/rollback path for existing clients.
