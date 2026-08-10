# Deployment rollback

## Symptom

Smoke, SLO, security, migration, or observability readiness fails after a
candidate deployment.

## Alert

Alert on failed go-live check, deployment revision, image digest, environment
manifest revision, and structured rollback reason.

## Impact

Promotion stops. The candidate must not become or remain the production desired
state when a mandatory gate fails.

## Diagnosis

Inspect the evidence pack, Git revision, immutable image digest, configuration
revision, migration state, ArgoCD health/drift, and Smoke/SLO results.

## Mitigation

Freeze promotion and preserve evidence. CI must not directly apply production
resources.

## Rollback / failover

Revert the environment manifest to the prior reviewed Git revision and allow
ArgoCD to reconcile the previous image/config. Product bindings remain pending
`TASK-M3-004`.

## Verification

Verify Git desired state, workload health, active image/config revisions,
Smoke/SLO checks, migration compatibility, and absence of drift.

## Escalation

Use the deployment owner, production approval record, and on-call escalation
policy; direct contact details remain outside the repository.
