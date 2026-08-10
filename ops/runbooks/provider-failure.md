# Provider failure

## Symptom

A Provider attempt times out, returns a normalized failure, or becomes
unavailable.

## Alert

Alert on Provider outcome/reason code, latency, retry count, fallback count,
quota state, and terminal request outcome without exposing endpoints or keys.

## Impact

Requests may retry or use an explicitly planned fallback. Exhaustion returns the
published Provider-failure HTTP semantic.

## Diagnosis

Inspect opaque Provider ID, model alias, tenant/config version, attempt plan,
quota/health evidence, and normalized failure reason.

## Mitigation

Use only candidates and attempts in the published Runtime Snapshot. Do not add
an emergency Provider or credential directly in the online process.

## Rollback / failover

Roll back the canary/config revision or immutable Gateway image. Weight steps,
observation windows, and automatic progression require reviewed configuration.

## Verification

Run Provider Mock failure injection and confirm retry/fallback telemetry,
non-blocking Usage emission, final response, and tenant isolation.

## Escalation

Use the Provider component owner and versioned escalation policy.
