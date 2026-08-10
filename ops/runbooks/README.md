# Runbook set

Critical failure-mode runbooks:

- [Control Plane unavailable](control-plane-unavailable.md)
- [Redis unavailable](redis-unavailable.md)
- [Provider failure](provider-failure.md)
- [Configuration publication failure](configuration-publication-failure.md)
- [Database migration failure](database-migration-failure.md)
- [Deployment rollback](deployment-rollback.md)

Every runbook covers symptom, alert, impact, diagnosis, mitigation,
rollback/failover, verification, and escalation. Numeric thresholds, direct
contacts, and product-specific commands remain in reviewed bindings rather than
being invented here. On-call assignments and tooling remain `TBD-020`.

The product-neutral on-call and approval interfaces are defined in
[`../coordination/`](../coordination/README.md). Concrete system bindings must
be published separately before production promotion.
