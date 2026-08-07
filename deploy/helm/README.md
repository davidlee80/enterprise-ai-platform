# Helm deployment model

`gateway/` is the first deployable chart and implements `TASK-M3-002`.
Environment differences are values overlays over one maintainable template:

- `values-dev.yaml`
- `values-test.yaml`
- `values-prod.yaml`

The Gateway chart contains no Kubernetes `Secret`, plaintext credential,
Control Plane database connection, cloud-specific node pool, namespace,
Ingress domain, certificate issuer, or storage class. Existing Secret names may
only be referenced through `imagePullSecrets`. Namespace/domain/certificate/
storage choices remain `TBD-019`; Secret Manager remains `TBD-012`.

`TASK-M3-002` covers the Gateway portion of `REQ-HELM-001`. Control Plane,
Runtime, observability, and dependency charts are remaining later scoped deliverables
and are not represented by empty or misleading charts here.

See `gateway/README.md` for validation, environment rendering, upgrade, and
rollback commands.
