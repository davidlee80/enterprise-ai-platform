# Gateway production image

`production-image-boundary.v1.json` is the executable readiness boundary for
`TASK-M3-001`. Run it through:

```powershell
powershell -NoProfile -File .\scripts\task.ps1 test-m3-001
```

## Current state

The boundary is `blocked-tbd-001`. `TBD-001` has not selected a backend
language/Web Framework, and the repository therefore has no production
application artifact, entrypoint, package manager, or dependency lock file.
There is intentionally no `Dockerfile`: inventing a runtime or shipping a
non-functional placeholder would violate the Codex Guardrails and
`REQ-BLD-004`.

The guard passes only when this unresolved state is explicit and no hidden
runtime selection has been committed. It does **not** claim that `AC-BLD-001`
has passed.

## Completion transition

After a reviewed ADR resolves `TBD-001`, change the boundary to
`implemented-v1` and provide every selected field plus the referenced lock
file and Dockerfile. The validator then requires:

- at least two digest-pinned build stages and an explicit artifact copy;
- a minimal final stage with no package-manager installation;
- a numeric, non-zero final `USER`;
- port `8080`, `/healthz`, and `/readyz` runtime contracts;
- source/revision/version OCI traceability labels while the exact tag format
  remains `TBD-013`;
- a CI SBOM artifact and image-signing capability;
- no credential-shaped `ARG`, `ENV`, copied Secret, or Secret-bearing layer.

Final acceptance also requires an actual image build, image inspection,
container probe tests, SBOM generation, image/history scanning, and
failure-injection evidence. Static boundary validation alone is insufficient.

Rollback before runtime selection is a source-control revert. After an image is
implemented, rollback selects a previously verified immutable image digest; it
must not rebuild an old mutable tag.

