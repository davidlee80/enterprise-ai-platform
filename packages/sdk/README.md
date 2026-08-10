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

The versioned pipeline boundary lives in [`contracts/`](contracts/). Contract
validation, compatibility checking, and generation planning are executable;
client generation, generated-client testing, and package publishing remain
disabled and explicitly blocked by `TBD-007`. The boundary also leaves the
output root and package registry unset, preventing an unresolved plan from
creating or publishing misleading artifacts.

```powershell
pwsh -NoLogo -NoProfile -File ./packages/sdk/generate.ps1 validate
pwsh -NoLogo -NoProfile -File ./packages/sdk/sdk-generation.conformance.ps1
pwsh -NoLogo -NoProfile -File ./scripts/task.ps1 test-tbd-007
```

Every future generated package must record the exact OpenAPI SHA-256 input and
package version. Rollback restores the prior package built from its recorded
contract digest; it must not regenerate a changed contract under an old version.
Language set, generator product/version, output layout, package registry, and
monorepo release topology remain pending review.

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
