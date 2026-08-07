# Deployment assets

- `helm/` contains Helm charts and values.
- `images/` contains production image readiness contracts and, once approved,
  component Dockerfiles.
- `kubernetes/` contains native Kubernetes resources or environment overlays.
- `terraform/` contains infrastructure-as-code modules and environments.

The Gateway Helm chart and cloud-neutral Terraform contracts are the first
concrete deployment assets. Provider resources and other charts are delivered
after their architecture decisions. Production namespace, domain, storage
class, cloud provider, and Secret Manager selections remain TBD.
The Gateway production image is explicitly blocked by `TBD-001`; see
`images/gateway/README.md` for the executable transition criteria.
