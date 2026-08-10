# Provider canary contracts

`TBD-014` is implemented as a configurable, versioned boundary for controlled
Provider changes. The policy schema can carry baseline and canary Provider IDs,
ordered stages, weights, observation windows, sample sizes, criteria references,
and allocation references after those values are approved. This repository does
not select production values for any of them.

The exact weight ladder, observation windows, minimum sample sizes, signal set,
promotion and rollback thresholds, allocation key, allocation algorithm, and
automatic progression behavior remain `TBD-014`. Any numbers and reference names
inside `provider-canary.conformance.ps1` are isolated test fixtures. They are not
defaults, recommendations, or production policy.

The Data Plane consumes an already published, tenant-scoped `config_version` and
policy revision. It never queries Control Plane PostgreSQL on the request path.
Tenant, configuration, revision, and model-alias mismatches are structured
indeterminate decisions. Region, compliance, enablement, and other hard policy
filters run before any future weighted selection; a canary policy cannot restore
a candidate removed by those filters.

Observation and Usage/Billing/Audit/Analytics persistence are asynchronous and
do not block routing. Incomplete windows, insufficient samples, unavailable
signals, missing criteria, or an unconfigured policy hold progression. A
production publication requires an explicitly reviewed policy and preserves the
last valid snapshot on failure.

Each published policy has a revision and rollback revision. Rollback selects a
previously validated policy snapshot; it does not mutate the active revision in
place. Decisions expose only opaque Provider IDs and structured reason codes—no
endpoint, credential, prompt/body, secret, raw Provider error, or stack trace.

Run the conformance suite:

```powershell
pwsh -NoLogo -NoProfile -File ./docs/contracts/provider-canary/provider-canary.conformance.ps1
```

The Router link is recorded in
[`router-boundary.v1.json`](../router/router-boundary.v1.json). Update the
compatibility baseline only with an explicitly reviewed migration and rollback
plan.
