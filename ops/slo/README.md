# SLI, SLO, and Dashboard boundary

This directory implements the `TBD-010` development handling: Dashboard models
support separately published targets, but no production SLI/SLO number is
selected.

[`sli-catalog.v1.json`](sli-catalog.v1.json) defines logical indicators for
request success, p95/p99 latency, TTFT, Provider success, configuration publish
success, and configuration propagation latency. Metric/query bindings remain
null so this task does not select an observability backend or metric naming
standard.

[`dashboard-model.v1.json`](dashboard-model.v1.json) provides panels and stable
bindings to logical indicators and future target-policy fields. It has no data
source, active target policy, alert threshold, burn-rate window, or release-gate
number. [`slo-target-policy.v1.schema.json`](slo-target-policy.v1.schema.json)
provides the versioned configuration entry point required before those values
can be published.

All production targets remain `TBD-010`, including availability/success ratios,
P95/P99 latency, TTFT, Provider availability, configuration propagation,
measurement windows, alert thresholds, and error-budget behavior. A reviewed SLO
policy must define them and bind the Dashboard/alerts/release gate to the same
revision. Rollback restores the prior target policy and its matching alert/gate
configuration.

Telemetry may use `tenant_id` only as a controlled dimension. `request_id`,
`trace_id`, and `user_id` are forbidden as metric labels; Prompt/Response bodies
and Provider secrets are forbidden.

Run from the repository root:

```powershell
pwsh -NoLogo -NoProfile -File ./ops/slo/slo-dashboard.conformance.ps1
pwsh -NoLogo -NoProfile -File ./scripts/task.ps1 test-tbd-010
```
