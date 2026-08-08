# SDK

Reusable client and generated-contract artifacts. SDKs must remain synchronized
with stable API contracts; the supported language set is `TBD-007`.

`generate.ps1 plan` validates and hashes the authoritative
[`openapi.yaml`](../../docs/contracts/openapi/openapi.yaml) as the SDK generation
input. It intentionally does not select a generator or language while `TBD-007`
is unresolved:

```powershell
pwsh -NoLogo -NoProfile -File ./packages/sdk/generate.ps1 plan
```

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
