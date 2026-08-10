# Deprecation contracts

`TBD-015` is implemented as a configurable, versioned deprecation workflow for
APIs, model aliases, configuration fields, and capabilities. A published policy
can carry explicit announcement, window-start, and window-end timestamps plus
replacement, migration, notification, enforcement, exception, revision, and
rollback references.

No production window duration, duration syntax, announcement/start/end rule,
notification channel, post-window enforcement action, or exception policy is
selected here. Values and timestamps in `deprecation.conformance.ps1` are
isolated test fixtures, not defaults or recommendations.

Publishing a scheduled deprecation requires explicit start and end timestamps;
the end must follow the start, and removal before the end is forbidden. The
evaluation contract reports `not_started`, `in_window`, `window_elapsed`,
`unconfigured`, `invalid`, or `indeterminate`. It does not itself disable a
resource. If the window elapsed without a reviewed enforcement reference, the
workflow holds for review instead of inventing a removal behavior.

The Data Plane consumes a tenant/config/revision-scoped published snapshot and
never queries Control Plane PostgreSQL on the request path. Notifications and
Usage/Billing/Audit/Analytics persistence are asynchronous and non-blocking.
Every decision is structured and secret/body-free; high-cardinality resource
and request identifiers are excluded from metric labels.

Rollback restores a previously validated policy revision and retains the prior
contract or resource through the configured window. `/v1` breaking changes
still require an explicit version and migration path.

Run the conformance suite:

```powershell
pwsh -NoLogo -NoProfile -File ./docs/contracts/deprecation/deprecation.conformance.ps1
```
