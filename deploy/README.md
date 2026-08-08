# Deployment assets

- `helm/` contains Helm charts and values.
- `images/` contains production image readiness contracts and approved
  component Dockerfiles.
- `kubernetes/` contains native Kubernetes resources or environment overlays.
- `terraform/` contains infrastructure-as-code modules and environments.

The Gateway Helm chart and cloud-neutral Terraform contracts are the first
concrete deployment assets. Provider resources and other charts are delivered
after their architecture decisions. Production namespace, domain, storage
class, cloud provider, and Secret Manager selections remain TBD.
The Gateway Linux runtime and Dockerfile are selected by `ADR-001`; image
acceptance remains blocked on the repository-wide supply-chain tooling in
`REQ-CICD-004` and `TASK-CICD-001`. See `images/gateway/README.md`.
