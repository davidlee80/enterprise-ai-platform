# Operations coordination interfaces

These versioned, product-neutral contracts define the boundary between the
platform and future on-call and production-approval systems.

- `on-call-binding.v1.schema.json` carries only opaque adapter, schedule,
  escalation-policy, and contact-target references.
- `approval-request.v1.schema.json` binds a production change to the complete
  go-live evidence pack.
- `approval-decision.v1.schema.json` returns a structured, auditable decision.
- `go-live-evidence-pack.v1.schema.json` requires references to test, security,
  configuration/version, deployment, migration, SLO/Smoke, capacity,
  observability, runbook, and rollback evidence.
- `operations-coordination-boundary.v1.json` records the fail-closed promotion
  rules and keeps both product selections explicitly unconfigured.

Direct contact details, credentials, and free-form evidence are forbidden in
these interfaces. An unconfigured or unavailable approval system blocks
production promotion, but neither approval nor on-call lookup is allowed on the
online data-plane request path.

Concrete products, role bindings, approver counts, separation-of-duty rules,
outage procedures, schedules, escalation policies, and contact targets remain
`TBD-020`.
