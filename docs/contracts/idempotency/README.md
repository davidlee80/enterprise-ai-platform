# Admin write idempotency contract

This directory implements the `TBD-005` development instruction—**contract
extension point**, not a production decision—for `REQ-GEN-013` and
`REQ-API-007`.

The versioned request and decision schemas normalize authenticated management
write context independently of HTTP transport. The boundary applies to create,
patch, publish, and rollback operations, preserves tenant/config-version
context, emits structured outcomes, and requires audit delivery through the
transactional outbox. Raw idempotency keys must not appear in decisions, logs,
errors, traces, metrics, or audit payloads.

## Unresolved production decisions

`idempotency-boundary.v1.json` deliberately leaves the following values null:

- transport Header name;
- TTL;
- storage profile;
- duplicate replay-response strategy;
- key/fingerprint conflict response strategy;
- store-failure strategy.

They remain `TBD-005`. An implementation may not publish an active idempotency
policy until a reviewed ADR/configuration revision fills all six fields. The
policy schema carries the version, revision, effective time, rollback revision,
and content hash required by `REQ-GEN-003`; the previous published policy must
remain available as the rollback target.

The normalized `duplicate` and `conflict` outcomes do not choose an HTTP status
or response body. Those mappings remain `TBD-005` and `TBD-008`. The
conformance test uses an in-memory mock only to prove tenant isolation,
fingerprint distinction, structured reasons, and non-disclosure; it does not
select the production storage medium or retention behavior.

Run from the repository root:

```powershell
pwsh -NoLogo -NoProfile -File ./docs/contracts/idempotency/idempotency-boundary.conformance.ps1
pwsh -NoLogo -NoProfile -File ./scripts/task.ps1 test-tbd-005
```

Schema rollback retains all v1 files and the compatibility baseline. A future
breaking contract revision requires a new version plus an explicit migration
and rollback plan; changing an active policy rolls back by publishing its
recorded `rollback_revision`, never by editing runtime cache state directly.
