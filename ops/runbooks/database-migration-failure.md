# Database migration failure

## Symptom

A forward migration fails, exceeds its operational window, or breaks
compatibility checks.

## Alert

Alert on migration identifier, structured failure reason, duration, lock impact,
and application/schema compatibility state.

## Impact

The release must not promote. The currently running application must retain
access to the prior compatible schema.

## Diagnosis

Inspect migration hash/history, transaction result, locks, backfill progress,
and expand/compatible/backfill/contract phase. Never log database credentials.

## Mitigation

Stop the rollout, release locks safely, retain compatible columns, and correct
the forward migration. Destructive emergency edits are prohibited.

## Rollback / failover

Roll back application and configuration revisions while keeping expanded schema
compatible. Use a reviewed forward repair for schema changes.

## Verification

Run empty-database migration, N-1 compatibility, failure rollback, and current
application reads against the resulting schema.

## Escalation

Use the DB owner, change approval, and incident escalation-policy references.
