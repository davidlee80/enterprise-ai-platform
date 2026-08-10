# KMS and Secret integration contract

Accepts only key purposes and references to reviewed audit, rotation, and
break-glass workflows. It never accepts key material, passwords, tokens, or
Provider keys. Envelope encryption is mandatory. Concrete KMS and Secret
Manager products remain `TBD-011`/`TBD-012`.

`secret_manager_integration_ref`, rotation, and break-glass references bind to
the product-neutral [`secret_ref` resolution boundary](../../../../docs/contracts/secrets/README.md).
They never carry credential or key material.
