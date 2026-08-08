# Architecture Decision Records

This directory stores reviewed Architecture Decision Records for choices that the
requirements intentionally leave unresolved.

An ADR must identify the affected `REQ-*`, `TASK-*`, and `TBD-*` entries and
record its review status. It must describe context, decision, compatibility
impact, security/tenant impact, and the rollback or replacement path. An ADR must
not silently override `DEVELOPMENT-REQUIREMENTS.md` or declare a production
standard before review.

`TASK-M0-002` creates this storage boundary only. No architecture decision is
made by this README.

Accepted Gateway decisions:

- `ADR-001-gateway-dotnet-linux-runtime.md` resolves `TBD-001`.
- `ADR-002-gateway-ddd-dependency-injection.md` resolves `TBD-002` for the
  Gateway without setting an unimplemented service-wide standard.
- `ADR-003-router-plugin-method-signature.md` resolves `TBD-003` for the
  Gateway with an async, cancellable, registry-composed plugin port.
- `ADR-004-opa-policy-runtime.md` resolves `TBD-004` for the Gateway with an
  OPA Data API sidecar behind a replaceable application port.
