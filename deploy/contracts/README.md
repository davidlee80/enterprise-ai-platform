# Deployment configuration contracts

Machine-readable, provider-neutral deployment input boundaries shared by Helm,
Terraform, and future GitOps composition. These contracts define configurable
entry points without publishing production environment identities.

`TBD-019` keeps the production domain, Kubernetes Namespace, certificate issuer,
and StorageClass unset until reviewed environment configuration supplies them.
