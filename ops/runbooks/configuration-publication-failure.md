# Configuration publication failure

## Symptom

A configuration revision commits incompletely, Outbox publication fails, or a
candidate Runtime Snapshot cannot be validated or activated.

## Alert

Alert on publication stage, structured reason code, revision, propagation
latency, and active-versus-candidate version.

## Impact

The candidate revision remains inactive and the last validated Snapshot must
continue serving requests.

## Diagnosis

Trace the PostgreSQL transaction, Outbox event, compiler result, Redis publish,
notification, content hash, and Data Plane validation for the affected tenant.

## Mitigation

Stop further promotion, correct the draft configuration, and republish through
the normal authorized lifecycle. Never patch Redis directly.

## Rollback / failover

Publish the recorded rollback revision and atomically restore it. Preserve the
failed revision and structured evidence for audit.

## Verification

Verify active revision, content hash, tenant isolation, propagation metrics,
and that new requests record the restored `config_version`.

## Escalation

Use the owning component and production approval/on-call interfaces.
