# Repository scripts

On Linux, `task.sh` is the repository command entrypoint. It resolves its own
location, requires PowerShell 7 (`pwsh`), and forwards arguments without shell
evaluation:

```bash
./scripts/task.sh lint
./scripts/task.sh test
./scripts/task.sh test-linux
./scripts/task.sh test-m0-002
./scripts/task.sh test-m0-003
./scripts/task.sh test-m1-001
./scripts/task.sh test-m1-002
./scripts/task.sh test-m1-003
./scripts/task.sh test-m1-004
./scripts/task.sh test-m2-001
./scripts/task.sh test-m2-002
./scripts/task.sh test-m2-003
./scripts/task.sh test-m2-004
./scripts/task.sh test-m2-005
./scripts/task.sh test-m2-006
./scripts/task.sh test-m2-007
./scripts/task.sh test-m3-001
./scripts/task.sh test-m3-002
./scripts/task.sh test-m3-003
./scripts/task.sh security
./scripts/task.sh build
```

`linux-smoke.sh` is executed by the Ubuntu PR gate. It verifies Linux,
PowerShell 7, the pinned Helm/Terraform versions, LF entrypoints, executable
bits, case-sensitive path safety, and then invokes the repository through the
Bash entrypoint:

```bash
./scripts/linux-smoke.sh
```

On Windows, call `task.ps1` with PowerShell 7 directly, for example
`pwsh -NoLogo -NoProfile -File .\scripts\task.ps1 lint`.

PostgreSQL migration commands use the separate entrypoint. The following
PowerShell 7 form works on Linux and Windows:

```powershell
pwsh -NoLogo -NoProfile -File ./scripts/migration.ps1 validate
pwsh -NoLogo -NoProfile -File ./scripts/migration.ps1 up
pwsh -NoLogo -NoProfile -File ./scripts/migration.ps1 status
```

The dedicated `test-m0-002` command validates the public-contract and ADR storage
boundaries without treating placeholders as published schemas. The general
`test-m0-003` command validates the PR workflow, least-privilege settings, and
forbidden deployment paths. The `security` command is a bootstrap credential
pattern check. The general `test` and `build` commands include the task-specific
validation as regression gates.

`test-m1-001` validates the confirmed baseline DDL, pending schema decision
register, expand/backfill/contract examples, rollback policy, and CI empty-
database test definition. `migration.ps1` uses `psql` as a client without
selecting a third-party migration product as the platform standard.

`test-m1-002` validates the Event Envelope v1 JSON Schema, Outbox table and SQL
coordination functions, transactional write template, duplicate-delivery
semantics, structured failure reason, and CI integration test definition.

`test-m1-003` validates the Runtime Snapshot v1 Schema, tenant hash-tag key
contract, immutable version and CAS current-pointer scripts, structured failure
reasons, rollback boundary, and isolated Redis integration test definition.

`test-m1-004` executes the Data Plane Snapshot Consumer conformance suite and
validates the notification schema/stream, tenant/version/hash validation,
duplicate and out-of-order handling, atomic in-memory reference exchange,
last-snapshot failure behavior, rollback, and config-version/staleness telemetry.
The executable reference does not select the production backend language.

`test-m2-001` executes the OpenAPI 3.1 schema/contract validator, `/v1` fixture
tests, compatibility-baseline check, language-neutral Gateway binding check, and
SDK generation-input plan. The contract does not select a server framework, SDK
language, custom API-key Header, or complete error body.

`test-m2-002` executes the Bearer/API Key authentication-boundary conformance
suite and validates the versioned request/decision schemas, verified tenant
principal, structured denial reasons, credential non-disclosure, Gateway
binding, OpenAPI traceability, and unresolved Header/IdP/runtime boundaries.

`test-m2-003` validates Policy Evaluation/Decision v1 schemas, authentication
and Gateway pipeline bindings, structured allow/deny/indeterminate semantics,
tenant/config-version isolation, required obligation types, policy mock
scenarios, and the unresolved `TBD-004`/`TBD-017` boundaries.

`test-m2-004` validates Router request/plugin-result/decision/registry v1
schemas, compatibility baseline, Policy/Gateway bindings, registry-driven
composition, dynamic mock-plugin registration, structured failures, obligation
handling, secret-free candidates, and `TBD-003`/`TBD-014` boundaries.

`test-m2-005` validates Provider invocation/config/result/registry v1 schemas,
the compatibility baseline, Router/Gateway bindings, single-attempt native and
LiteLLM mocks, structured error normalization, tenant/config isolation, secret
non-disclosure, and the platform-owned Retry/Fallback handoff.

`test-m2-006` validates Retry/Fallback request/plan/result/telemetry v1 schemas,
the compatibility baseline, explicit plan semantics, Provider failure
injection, retry/fallback order, non-retryable stop, plan exhaustion,
tenant/config isolation, structured telemetry, high-cardinality label guards,
secret safety, and unresolved production timing/public-error decisions.

`test-m2-007` validates Event Envelope/UsageObserved/result schemas,
compatibility baseline, non-blocking enqueue and response release, asynchronous
publish failure, duplicate event/business-key consumption, tenant isolation,
token/cost observation shape, high-cardinality label guards, secret/body
non-disclosure, and the unresolved transport/storage/pricing decisions.

`test-m3-001` restores the exact .NET 10 SDK graph in locked mode, builds the
Gateway, probes `/healthz` and fail-closed `/readyz`, verifies log/body Secret
non-disclosure, and validates the versioned production-image boundary and
Dockerfile. CI also builds and probes the Linux image. The boundary reports
`runtime-implemented` with `acceptance=not-met` until `REQ-CICD-004` and
`TASK-CICD-001` select and wire SBOM, scanner, signing, and evidence tooling.

`test-m3-002` runs real Helm lint/template checks for the Gateway chart and all
three environment overlays. It verifies the 3-replica/8080 baseline, readiness,
liveness and startup probes, resources, Service, PodDisruptionBudget, topology
spread, workload security, production image-reference failure guards, immutable
digest rendering, and the absence of Secret resources or a fixed namespace.

`test-m3-003` runs Terraform formatting checks and initializes, validates, and
plans all three provider-free environment compositions using an explicitly
non-production fixture. It rejects unapproved provider/resource/backend blocks,
vendor-specific resource names, and credential-shaped assignments while
checking all eight required modules and cloud-neutral architecture contracts.

OpenAPI-specific commands are also available directly:

```powershell
pwsh -NoLogo -NoProfile -File ./scripts/openapi.ps1 validate
pwsh -NoLogo -NoProfile -File ./scripts/openapi.ps1 compatibility
pwsh -NoLogo -NoProfile -File ./packages/sdk/generate.ps1 plan
```

The runner uses structured `reason_code` values for validation failures. The
Gateway runtime decision is recorded separately in `docs/adr/ADR-001-*`.

`test-linux` statically validates the LF policy, Bash entrypoints, Linux-first
documentation, structured missing-dependency failure, case-collision guard, and
Ubuntu smoke-test wiring. `linux-smoke.sh` supplies the host-specific evidence
that cannot be produced by this static command on Windows.

The general `test`/`build` commands require .NET SDK 10.0.302, Helm v3.21.3,
and Terraform 1.15.8 because they include the real M3 gates. The PR workflow
installs all three through commit-SHA-pinned actions; local runs must place
compatible `dotnet`, `helm`, and `terraform` binaries on `PATH`.
