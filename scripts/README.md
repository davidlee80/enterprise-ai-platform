# Repository scripts

On Linux, `task.sh` is the repository command entrypoint. It resolves its own
location, requires PowerShell 7 (`pwsh`), and forwards arguments without shell
evaluation:

```bash
./scripts/task.sh lint
./scripts/task.sh test
./scripts/task.sh test-linux
./scripts/task.sh test-code-001
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

`test-code-001` validates ADR-002, the compile-time
`Domain -> Application -> Infrastructure -> Api/Host` dependency graph, the
framework-free Domain boundary, locked project graphs, built-in .NET DI
container validation, fail-closed default adapter, and replaceable Fake adapter.
It does not select the remaining Router, Policy, Provider, Retry, or Usage
method signatures.

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

`test-tbd-005` validates the versioned management-write idempotency extension
point, compatibility baseline, OpenAPI linkage, tenant-scoped mock behavior,
structured decisions, audit/outbox boundary, config version/rollback fields,
and key non-disclosure. It also rejects any prematurely selected Header, TTL,
storage, replay/conflict response, or store-failure strategy.

`test-tbd-006` validates the versioned management-list pagination review
boundary, compatibility baseline, OpenAPI linkage, tenant-first filtering,
cursor and offset candidate continuity, structured invalid-position handling,
and configuration rollback metadata. It rejects any prematurely selected
strategy, query parameter name, page-size value, cursor policy, or consistency
behavior.

`test-tbd-007` validates the versioned SDK pipeline contract, compatibility
baseline, OpenAPI linkage/version/digest, ready validation/planning stages,
blocked generation/test/publish stages, and rollback rule. It rejects any SDK
language, generator/version, output directory, or package registry selected
before review.

`test-tbd-008` validates the versioned public HTTP error status boundary,
OpenAPI/compatibility synchronization, structured internal-context requirement,
and non-disclosure rules. It rejects any public body schema/content, field/code
mapping, media type, or `402` meaning published before API review.

`test-tbd-009` validates the versioned coverage-gate policy and compatibility
baseline, exercises comparison/invalid-input behavior with test-only fixtures,
and executes the real CI gate. `COVERAGE_MINIMUM_PERCENT` is deliberately unset
until review; once set, the gate fails unless `COVERAGE_OBSERVED_PERCENT` is
present and at or above the configured threshold.

`test-tbd-010` validates the versioned logical SLI catalog, target-policy
configuration schema, vendor-neutral Dashboard model, compatibility baseline,
rollback lifecycle, and telemetry-label safety. It fails if a production SLO,
data-source binding, alert/burn-rate rule, or release-gate threshold is selected
before the `TBD-010` review.

`test-tbd-011` validates the versioned cloud-provider selection schema,
provider-neutral boundary, compatibility baseline, local-module-only topology,
rollback lifecycle, and credential/state safety without requiring Terraform CLI.
It fails if a provider, location, adapter, identity, remote backend, vendor token,
provider implementation block, or remote module source is selected before the
`TBD-011` review.

`test-tbd-012` validates the opaque `secret_ref`, resolution request/decision,
versioned Secret Manager binding, compatibility baseline, Provider/KMS linkage,
and an in-memory resolver conformance suite. It covers normal delivery, tenant
and config isolation, missing/denied/unavailable secrets, audit failure, invalid
rotation state, break-glass isolation, delivery failure, rollback guards, and
secret-free decisions without selecting a product or reference format. Audit
enqueue rejection is observed without blocking an otherwise authorized delivery.

`test-tbd-013` validates the versioned Image Tag policy schema, immutable image
publication record, compatibility baseline, Gateway OCI-label linkage, explicit
build metadata, digest identity, and rollback guard. It exercises digest-only
release evidence, test-only Tags, label mismatch, placeholder revision, invalid
digest, and release-Tag blocking while the production Tag format is unresolved.

`test-tbd-014` validates the versioned Provider canary policy, observation, and
decision schemas, compatibility baseline, Router linkage, asynchronous
observation boundary, structured hold/promote/rollback reasons, tenant and
configuration isolation, hard-filter precedence, and revision rollback. Exact
weights, windows, samples, signals, thresholds, allocation behavior, and
automatic progression remain unconfigured; script values are test-only fixtures.

`test-tbd-015` validates the versioned deprecation policy and evaluation schemas,
compatibility baseline, API/model-alias/config-field/capability coverage,
OpenAPI linkage, explicit window ordering, lifecycle states, tenant/config/
revision/resource isolation, asynchronous notification, and rollback. Window
duration/syntax, scheduling, notification channels, enforcement, and exception
behavior remain unconfigured; timestamps are test-only fixtures.

`test-tbd-016` validates the versioned Runtime Snapshot staleness policy,
compatibility baseline, optional Snapshot linkage, existing Consumer binding,
tenant/config/revision isolation, positive configured inputs, null production
default, raw staleness metrics, Redis-failure fallback, and rollback guards.
The production maximum remains unset and threshold-exceeded behavior remains
`TBD-017`; numeric values are test-only fixtures.

`test-tbd-018` validates the versioned Ownership Catalog and record schema for
all applications and shared packages, required operational metadata links,
component completeness/uniqueness, and production-assignment guards. Concrete
organization names, owner references, and team topology remain unconfigured.

`test-tbd-019` validates the production-environment settings schema, Helm values
and schema, Terraform root variables, compatibility baseline, complete-setting
guard, provider neutrality, and rollback lifecycle. Domain, Namespace,
certificate issuer, and StorageClass remain empty/null in the repository.

`test-tbd-020` validates the product-neutral on-call and approval schemas,
required go-live checks, structured evidence, unconfigured/unavailable
fail-closed promotion behavior, online Data Plane independence, sensitive-field
guards, and revision rollback. All concrete coordination systems and bindings
remain unconfigured.

`test-m4-004` validates the performance regression profile and evaluator. It is
measure-only until all reviewed thresholds are configured and does not claim
real-environment load evidence.

`test-m4-005` validates the nine-threat control matrix, Secret scan, Data Plane
database separation, tenant-mismatch evidence, and fail-closed production
readiness while required controls remain incomplete.

`test-m5-002` validates the six critical failure-mode runbooks and all required
operational sections. `test-m5-003` validates the configurable capacity and
Provider/Region N-1 model without selecting production values.

`test-readiness-gate` proves that the production aggregator detects every
currently known mandatory blocker. `production-readiness` evaluates real
repository state and intentionally returns nonzero until required tables,
runtime adapters, supply-chain/GitOps assets, production profiles, owners,
on-call, and approval evidence are configured.

Coverage-gate commands are also available directly:

```powershell
pwsh -NoLogo -NoProfile -File ./scripts/coverage-gate.ps1 validate
pwsh -NoLogo -NoProfile -File ./scripts/coverage-gate.ps1 self-test
```

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
