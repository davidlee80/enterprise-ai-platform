# Redis unavailable

## Symptom

Snapshot fetch/publication fails or Redis connectivity is unavailable.

## Alert

Alert on Snapshot read/publish reason codes, Redis availability, and raw
staleness. Thresholds and maximum permitted staleness remain reviewed policy.

## Impact

The Data Plane continues with its last validated in-memory Snapshot. New
configuration cannot become active until Redis recovers.

## Diagnosis

Check Redis service health, tenant-scoped Snapshot keys, notification backlog,
content hashes, current revision, and the in-memory active version.

## Mitigation

Preserve the in-memory Snapshot, restore Redis, replay version notification if
required, and reject invalid or cross-tenant Snapshot data.

## Rollback / failover

Use the versioned rollback script to restore the prior Snapshot pointer. Never
delete retained revisions or query Control Plane PostgreSQL from the Data Plane.

## Verification

Verify tenant/config/hash validation, atomic swap, active version, staleness,
and that in-flight requests retain their original context.

## Escalation

Use the reviewed cache owner and on-call escalation-policy references.
