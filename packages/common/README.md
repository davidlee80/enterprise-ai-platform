# Common

Reusable technical primitives only.

This package must not contain domain business logic. It also must not contain
cross-domain repositories or direct access to business tables. Domain behavior
belongs to the owning application and crosses boundaries through stable APIs or
versioned events.

## Ownership metadata

| Field | Value |
|---|---|
| Owner | `TBD-018` |
| SLO | [Placeholder](../../ops/slo/README.md) |
| Runbook | [Placeholder](../../ops/runbooks/README.md) |
| Upgrade window | `TBD; assign with the component owner` |
| Data retention responsibility | `Not applicable at bootstrap; re-evaluate if persistence is introduced` |

Source is traceable by Git revision; release version topology remains TBD under
`REQ-REP-006`.
