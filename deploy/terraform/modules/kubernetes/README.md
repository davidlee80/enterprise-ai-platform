# Kubernetes module contract

Requires independent `data-plane` and `runtime` node-pool contracts and carries
the Gateway capacity baseline from `REQ-HELM-002/003`. Provider-specific cluster
identity, CNI, ingress, Namespace, StorageClass, autoscaler, and accelerator
selection remain `TBD-011`/`TBD-019` inputs. Labels and taints are supplied by
reviewed environment configuration rather than hard-coded cloud conventions.

