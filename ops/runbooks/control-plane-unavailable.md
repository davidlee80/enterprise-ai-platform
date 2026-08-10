# Control Plane unavailable

## Symptom

Control Plane APIs or configuration publication are unavailable while the Data
Plane may still serve the last validated Runtime Snapshot.

## Alert

Alert on Control Plane availability and `config_publish` failure reason codes;
production thresholds remain bound through the reviewed SLO policy.

## Impact

Management changes and new configuration publication stop. Existing Data Plane
requests must not synchronously fall back to Control Plane PostgreSQL.

## Diagnosis

Check Control Plane health, PostgreSQL connectivity, Outbox backlog, active
Snapshot version, and Data Plane staleness without inspecting credentials or
request bodies.

## Mitigation

Freeze configuration changes, preserve the last validated Snapshot, restore
Control Plane dependencies, and verify Outbox publication resumes.

## Rollback / failover

Roll back the Control Plane deployment to the prior immutable image and schema-
compatible revision. Do not edit production Redis or Data Plane memory directly.

## Verification

Verify management health, a test publication, Snapshot propagation, active
`config_version`, and continued Data Plane service from the prior Snapshot.

## Escalation

Resolve the component owner and escalation target through the versioned on-call
binding under `ops/coordination`; direct contact details do not belong here.
