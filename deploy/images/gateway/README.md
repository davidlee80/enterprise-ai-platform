# Gateway production image

`production-image-boundary.v1.json` is the executable readiness boundary for
`TASK-M3-001`. Run it through:

```bash
./scripts/task.sh test-m3-001
```

## Current state

`ADR-001` resolves the Gateway runtime as C#/.NET 10, ASP.NET Core Minimal APIs,
Kestrel, and locked NuGet restore on Linux. `ADR-002` supplies the
Domain/Application/Infrastructure/Api project graph and built-in .NET DI
composition. The boundary is
`runtime-implemented-supply-chain-tbd`: the application and image can be built
and probed, while `AC-BLD-001` remains `acceptance=not-met` until
`REQ-CICD-004` and `TASK-CICD-001` select the repository-wide SBOM, scanner,
and signing tools and provide evidence.

## Implemented controls

The runtime boundary provides:

- at least two digest-pinned build stages and an explicit artifact copy;
- a minimal final stage with no package-manager installation;
- a numeric, non-zero final `USER`;
- port `8080`, `/healthz`, and `/readyz` runtime contracts;
- source/revision/version OCI traceability labels while the exact tag format
  remains `TBD-013`;
- mandatory explicit build arguments for source URL, committed revision, and
  source/release version, with no placeholder defaults;
- linkage to the repository-wide immutable image publication-record contract;
- an Ubuntu CI build, metadata inspection, and container probe test;
- no credential-shaped `ARG`, `ENV`, copied Secret, or Secret-bearing layer.

Run the image-only integration check on a Docker-capable host with:

```powershell
pwsh -NoLogo -NoProfile -File ./deploy/images/gateway/gateway-image.integration.ps1
```

## Remaining completion transition

After supply-chain tooling is reviewed, fill the currently null tool and
evidence fields, wire SBOM generation, scanning, and signing into CI, then move
the boundary to `implemented-v1`. Static validation and an unsigned local image
alone are insufficient for final acceptance.

Rollback selects a previously verified immutable image digest; it must not
rebuild an old mutable tag.
