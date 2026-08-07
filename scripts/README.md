# Repository scripts

`task.ps1` is the bootstrap command entrypoint:

```powershell
powershell -NoProfile -File .\scripts\task.ps1 lint
powershell -NoProfile -File .\scripts\task.ps1 test
powershell -NoProfile -File .\scripts\task.ps1 test-m0-002
powershell -NoProfile -File .\scripts\task.ps1 test-m0-003
powershell -NoProfile -File .\scripts\task.ps1 test-m1-001
powershell -NoProfile -File .\scripts\task.ps1 test-m1-002
powershell -NoProfile -File .\scripts\task.ps1 test-m1-003
powershell -NoProfile -File .\scripts\task.ps1 test-m1-004
powershell -NoProfile -File .\scripts\task.ps1 test-m2-001
powershell -NoProfile -File .\scripts\task.ps1 test-m2-002
powershell -NoProfile -File .\scripts\task.ps1 test-m2-003
powershell -NoProfile -File .\scripts\task.ps1 test-m2-004
powershell -NoProfile -File .\scripts\task.ps1 test-m2-005
powershell -NoProfile -File .\scripts\task.ps1 test-m2-006
powershell -NoProfile -File .\scripts\task.ps1 test-m2-007
powershell -NoProfile -File .\scripts\task.ps1 test-m3-001
powershell -NoProfile -File .\scripts\task.ps1 test-m3-002
powershell -NoProfile -File .\scripts\task.ps1 test-m3-003
powershell -NoProfile -File .\scripts\task.ps1 security
powershell -NoProfile -File .\scripts\task.ps1 build
```

PostgreSQL migration commands use the separate entrypoint:

```powershell
powershell -NoProfile -File .\scripts\migration.ps1 validate
powershell -NoProfile -File .\scripts\migration.ps1 up
powershell -NoProfile -File .\scripts\migration.ps1 status
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

`test-m3-001` validates the versioned production-image readiness boundary. In
the current `blocked-tbd-001` state it requires all runtime/package/base-image
choices and acceptance evidence to remain null, rejects an unapproved
Dockerfile, and verifies the mandatory multi-stage, digest pinning, minimal
runtime, numeric non-root, health, SBOM, traceability, rollback, and Secret-free
transition controls. A passing guard reports `acceptance=not-met`; it is not a
substitute for building and probing a real image after `TBD-001` is resolved.

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
powershell -NoProfile -File .\scripts\openapi.ps1 validate
powershell -NoProfile -File .\scripts\openapi.ps1 compatibility
powershell -NoProfile -File .\packages\sdk\generate.ps1 plan
```

The runner uses structured `reason_code` values for validation failures. It is a
repository utility, not a backend language or framework decision.

The general `test`/`build` commands require Helm v3.21.3 and Terraform 1.15.8
because they include the real `TASK-M3-002` and `TASK-M3-003` gates. The PR
workflow installs both through commit-SHA-pinned actions; local runs must place
compatible `helm` and `terraform` binaries on `PATH`.
