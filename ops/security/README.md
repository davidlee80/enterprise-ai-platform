# Security and threat validation

The threat-control matrix tracks every threat required by `REQ-TST-008` and
binds it to automated evidence where an implementation exists. Missing controls
remain explicit and block production readiness; the matrix does not convert a
contract placeholder into security approval.

`security-threat.conformance.ps1` verifies Secret safety patterns, Data Plane
database separation, sensitive-body logging guards, tenant-mismatch tests, and
the fail-closed readiness state. Dependency/image scanning, Input/Output
Guardrails, replay storage, and resource-exhaustion evidence remain required.
