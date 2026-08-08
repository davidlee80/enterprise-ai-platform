# Gateway Helm chart

This chart implements the Gateway Deployment baseline from `TASK-M3-002` and
keeps development, test, and production differences in values overlays.

## Validate

```bash
helm lint ./deploy/helm/gateway
helm template gateway ./deploy/helm/gateway --values ./deploy/helm/gateway/values-dev.yaml
helm template gateway ./deploy/helm/gateway --values ./deploy/helm/gateway/values-test.yaml
helm template gateway ./deploy/helm/gateway --values ./deploy/helm/gateway/values-prod.yaml --set-string image.digest="${GATEWAY_IMAGE_DIGEST}"
./scripts/task.sh test-m3-002
```

`GATEWAY_IMAGE_DIGEST` must be a reviewed `sha256:` digest. Production
rendering intentionally fails when neither a digest nor an explicit tag is
provided. The chart does not decide the `TBD-013` tag convention. Non-production
rendering may use the chart's clearly non-production `appVersion` only for
template validation; it is not a released Gateway image.

## Baseline and safety

Default values render 3 replicas, container port 8080, `/readyz`, `/healthz`, a
startup probe, the required requests/limits, a PodDisruptionBudget, and topology
spread. Pods disable service-account token mounting, require non-root execution,
use the runtime-default seccomp profile, drop Linux capabilities, disallow
privilege escalation, and use a read-only root filesystem.

Node isolation is exposed through generic `nodeSelector`, `tolerations`, and
`affinity` values. No cloud provider or node-pool convention is selected.

The chart creates no Secret and accepts no Provider/API credential values.
`imagePullSecrets` contains names of externally managed Kubernetes Secrets only.
Runtime request configuration remains tenant/config-version scoped through the
Runtime Snapshot boundary; the chart does not add a Control Plane PostgreSQL
dependency to the Data Plane.

## Upgrade and rollback

Before upgrade, verify API backward compatibility, expand/backfill/contract
migration phase, Runtime Snapshot compatibility, and the target immutable image
digest. Namespace is an external `TBD-019` input.

```bash
helm upgrade --install gateway ./deploy/helm/gateway --namespace "${GATEWAY_NAMESPACE}" --values ./deploy/helm/gateway/values-prod.yaml --set-string image.digest="${GATEWAY_IMAGE_DIGEST}" --atomic --wait
helm history gateway --namespace "${GATEWAY_NAMESPACE}"
helm rollback gateway "${GATEWAY_REVISION}" --namespace "${GATEWAY_NAMESPACE}" --wait
```

`--atomic` rolls a failed upgrade back to the prior Helm revision. Operational
rollback must select a previously verified immutable image digest and preserve
compatible database/config versions; it must not rebuild or reinterpret a
mutable tag. Production promotion and ArgoCD ownership remain `TASK-M3-004`, so
these commands are operator validation guidance rather than a CI direct-deploy
path.

Namespace, production domain, certificate issuer, and storage class remain
`TBD-019`; this Gateway-only chart does not invent them. Control Plane, Runtime,
observability, and dependency charts remain outstanding portions of
`REQ-HELM-001`.
