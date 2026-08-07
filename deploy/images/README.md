# Production image boundaries

This directory owns production container build inputs and machine-readable
readiness boundaries. A component may add a production `Dockerfile` only after
its runtime language, framework, package manager, dependency lock file,
artifact, and entrypoint have been approved.

The Gateway boundary is under `gateway/`. It deliberately remains blocked by
`TBD-001`; the repository currently has no application runtime or dependency
lock from which a functional production image can be built. A scratch,
shell-only, or otherwise non-functional placeholder image must not be presented
as satisfying `TASK-M3-001`.

