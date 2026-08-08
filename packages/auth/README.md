# Auth

Reusable authentication/authorization primitives and explicit tenant-security
context. Domain-specific IAM workflows remain in the IAM application.

This package must not contain domain repositories or directly read/write another
domain's business tables.

## Ownership metadata

| Field | Value |
|---|---|
| Owner | `TBD-018` |
| SLO | [Placeholder](../../ops/slo/README.md) |
| Runbook | [Placeholder](../../ops/runbooks/README.md) |
| Upgrade window | `TBD; assign with the component owner` |
| Data retention responsibility | `Not applicable at bootstrap; re-evaluate if persistence is introduced` |

Source is traceable by Git revision; release version topology remains TBD under
`REQ-REP-006`.

## Authentication Boundary v1

TASK-M2-002 provides a language-neutral authentication port for the Gateway:

- [`authentication-request.v1.schema.json`](contracts/authentication-request.v1.schema.json)
  accepts normalized `bearer` or `api_key` credential candidates. Transport
  Header extraction happens before this boundary.
- [`authentication-decision.v1.schema.json`](contracts/authentication-decision.v1.schema.json)
  emits an authenticated, denied, or indeterminate result with a structured
  `reason_code`. Only an authenticated result contains a verified principal.
- [`authentication-boundary.v1.json`](contracts/authentication-boundary.v1.json)
  defines verifier ports and safety invariants without selecting a runtime,
  Identity Provider, key store, or dependency-injection framework.

The verified principal is the only source of `tenant_id`; client request data
cannot supply or override it. Authentication establishes identity but does not
authorize access to a model or tenant resource. The structured principal must
enter the `TASK-M2-003` policy authorization boundary before request handling.
That boundary is now versioned at
[`policy-boundary.v1.json`](../../docs/contracts/policy-decisions/policy-boundary.v1.json).

The Data Plane verifier port must use locally available or published
verification material and must never synchronously query Control Plane
PostgreSQL. The publication/cache mechanism for API-key verification material,
including hashing, rotation, revocation, and retention, requires an ADR and does
not authorize the unresolved `api_key` table from the migration TBD register.

Credential values are write-only boundary inputs. They must not be persisted,
logged, added to metrics/traces, returned in decisions, or exposed through
public errors. Provider credentials are outside this package and remain
`secret_ref`-only. Secret Manager selection remains `TBD-012`.

Run the executable conformance suite from the repository root:

```powershell
pwsh -NoLogo -NoProfile -File ./packages/auth/authentication-boundary.conformance.ps1
```

The concrete OpenAPI Header/security scheme and Identity Provider remain
`REQ-API-003`. `ADR-001` selects C#/.NET 10 and ASP.NET Core, while `ADR-002`
selects the Gateway composition root without selecting the authentication
implementation. Complete public error bodies remain `TBD-008`.
