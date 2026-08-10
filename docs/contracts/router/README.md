# Router contracts

TASK-M2-004 defines a language-neutral registration/composition boundary:

- `router-request.v1.schema.json` carries policy-approved, tenant/version-scoped
  requests and opaque Provider candidates.
- `router-registry.v1.schema.json` maps a `route_strategy` to an ordered list of
  registered plugins.
- `router-plugin-result.v1.schema.json` defines structured results returned by
  the production method selected in `ADR-003`.
- `route-decision.v1.schema.json` records selection, reason, ordered candidates,
  plugin trace, and obligation handling.
- `router-boundary.v1.json` preserves pipeline invariants and the pending
  `TASK-M2-005` Provider Adapter boundary.

Adding a strategy plugin is a registry/composition change; it must not add a
strategy-specific branch to the core request lifecycle. The conformance suite
demonstrates this with dynamically registered mock plugins.

Candidate metadata is limited to opaque `provider_id`, region, priority, weight,
and enabled state. It never includes Provider endpoint, `secret_ref`, plaintext
key, or credential material. Weight is represented because it exists in the
confirmed data baseline, but its grey-release and observation semantics remain
`TBD-014`; this task does not define a weighted selection algorithm. The
configurable, versioned canary entry point is
[`provider-canary-boundary.v1.json`](../provider-canary/provider-canary-boundary.v1.json).
Its production weights, windows, samples, thresholds, signals, and allocation
algorithm remain unconfigured.

Only Policy Decision `allow` can enter routing. A `force_region` obligation is
enforced before plugin composition; other obligations are forwarded unchanged.
Only a `selected` Route Decision can enter `TASK-M2-005`. Indeterminate mapping
remains `TBD-017` and is never silently converted by this boundary. The Provider
Adapter is now versioned at
[`provider-adapter-boundary.v1.json`](../providers/provider-adapter-boundary.v1.json).

Routing uses the published registry/candidates for the same tenant and
`config_version`; the online Data Plane must not query Control Plane PostgreSQL.
No synchronous Usage, Billing, Audit, or Analytics write blocks routing.

Run the conformance suite:

```powershell
pwsh -NoLogo -NoProfile -File ./apps/router/router-plugin.conformance.ps1
```

The production language is selected by `ADR-001`, Gateway DI composition by
`ADR-002`, and the async/cancellable plugin signature by `ADR-003`. Route
algorithms, grey weights, and observation windows remain `TBD-014`. Update
`router-compatibility-baseline.v1.json` only with an
explicitly reviewed breaking-change and migration plan.
