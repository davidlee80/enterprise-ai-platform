# Production image boundaries

This directory owns production container build inputs and machine-readable
readiness boundaries. A component may add a production `Dockerfile` only after
its runtime language, framework, package manager, dependency lock file,
artifact, and entrypoint have been approved.

The Gateway boundary is under `gateway/`. `ADR-001` supplies a functional .NET
10 runtime, locked NuGet graph, and digest-pinned Linux Dockerfile. Runtime image
checks are executable locally and in CI; supply-chain acceptance stays open
until `REQ-CICD-004` and `TASK-CICD-001` select SBOM, scanner, and signing tools.
