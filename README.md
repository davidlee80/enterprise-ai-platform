# Enterprise AI Platform

This repository is the monorepo for the Enterprise AI Platform. The engineering
source of truth is [DEVELOPMENT-REQUIREMENTS.md](DEVELOPMENT-REQUIREMENTS.md).
Every change must map to its `REQ-*`, `TASK-*`, and acceptance criteria before
implementation.

## Repository map

| Path | Purpose |
|---|---|
| `apps/` | Independently buildable and deployable applications/services |
| `apps/gateway/src/EnterpriseAiPlatform.Gateway.*` | ADR-002 Gateway Domain, Application, Infrastructure, and Api/Host projects |
| `packages/` | Reusable technical components with no cross-domain business-table access |
| `packages/db/migrations/` | Versioned PostgreSQL migrations and schema decision register |
| `packages/db/outbox/` | Transactional event persistence and publisher coordination boundary |
| `packages/cache/snapshot-store/` | Versioned Redis Runtime Snapshot publication and rollback boundary |
| `packages/cache/snapshot-consumer/` | Data Plane Snapshot notification, validation, atomic swap, and staleness boundary |
| `packages/auth/contracts/` | Versioned Bearer/API Key authentication boundary and principal contract |
| `deploy/helm/` | Helm charts and values |
| `deploy/images/` | Production image readiness boundaries and approved component Dockerfiles |
| `deploy/kubernetes/` | Native Kubernetes resources and environment overlays |
| `deploy/terraform/` | Infrastructure as code |
| `ops/` | Ownership, SLO, runbook, alerting, and operational assets |
| `docs/` | Architecture, interface, ADR, and development documentation |
| `docs/contracts/` | Versioned public API, event, runtime, and policy contracts |
| `docs/contracts/openapi/openapi.yaml` | Authoritative OpenAPI 3.1 `/v1` contract |
| `docs/contracts/policy-decisions/` | Versioned Policy Evaluation and structured decision contracts |
| `docs/contracts/router/` | Versioned Router Plugin registry, result, and decision contracts |
| `docs/contracts/providers/` | Versioned Provider Adapter, runtime config, registry, and LiteLLM boundary contracts |
| `docs/contracts/retry-fallback/` | Versioned attempt plan, orchestration result, and telemetry contracts |
| `docs/contracts/events/usage/` | Versioned asynchronous Usage event and idempotent processing contracts |
| `docs/adr/` | Reviewed architecture decisions for explicitly unresolved choices |
| `.github/workflows/` | Pull-request lint, test, and security gates |
| `scripts/` | Development, validation, migration, and build entrypoints |

Application and package ownership metadata lives in each component README and
links to the shared placeholders under `ops/`. Concrete team names, upgrade
windows, and production SLO values remain TBD.

## Development commands

Linux is the primary development and CI execution environment. Install Bash,
Git, PowerShell 7 (`pwsh`), .NET SDK 10.0.302, Helm v3.21.3, and Terraform
1.15.8. Docker is also required for the image, PostgreSQL, and Redis integration
suites. From the repository root, run:

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

Run the Linux host/tool/version/entrypoint smoke check with:

```bash
./scripts/linux-smoke.sh
```

Validate or apply PostgreSQL migrations through the dedicated forward-only
entrypoint. The `up` and `status` commands also require `psql` on `PATH`:

```bash
pwsh -NoLogo -NoProfile -File ./scripts/migration.ps1 validate
pwsh -NoLogo -NoProfile -File ./scripts/migration.ps1 up
pwsh -NoLogo -NoProfile -File ./scripts/migration.ps1 status
```

On Windows, use PowerShell 7 directly, for example
`pwsh -NoLogo -NoProfile -File .\scripts\task.ps1 lint`. PowerShell is only the
repository task runner. The Gateway runtime is selected by
[`ADR-001`](docs/adr/ADR-001-gateway-dotnet-linux-runtime.md); Gateway DDD
projects and DI composition are selected by
[`ADR-002`](docs/adr/ADR-002-gateway-ddd-dependency-injection.md).
Component-specific commands are delegated from this entrypoint.

## Development boundaries

- Control Plane state and Data Plane request processing must remain separated.
- Tenant-owned access must carry `tenant_id`; shared packages must not query all
  tenants and filter in application code.
- Cross-domain integration uses stable APIs or versioned events, not shared
  business tables.
- Provider credentials are represented by `secret_ref`; plaintext secrets must
  not enter source, configuration, logs, or build output.
- Usage, Billing, Audit, and Analytics side effects do not block the online model
  request path.
- Request-affecting configuration must be versioned and rollback-capable.

The M0 bootstrap tasks introduce no runtime code, database, tenant data, or
production configuration. `TASK-M0-002` establishes contract storage boundaries
but does not publish an API, event, Runtime Snapshot, or Policy Decision schema.
Those contracts become executable in their corresponding dependent tasks.

`TASK-M0-003` adds pull-request lint, test, and bootstrap security jobs. The
security command is a limited credential-pattern check, not a final selection of
the production dependency, image, or Secret scanning tools.

`TASK-M1-001` adds only the requirement-defined PostgreSQL baseline tables. Other
mandatory business tables remain explicit, non-executable schema TBD items until
their domain fields and constraints are reviewed.

`TASK-M1-002` adds a transactional Outbox and Event Envelope v1. Broker delivery
runs in an independent worker and remains at-least-once; online requests never
wait for downstream Usage, Billing, Audit, or Analytics database writes.

`TASK-M1-003` adds a tenant-scoped Redis Runtime Snapshot Store with immutable
version records, compare-and-swap current pointers, structured failure reasons,
and retained-version rollback. Redis remains rebuildable publication state, not
the system of record. Notifications and Data Plane in-memory replacement are
provided by `TASK-M1-004`.

`TASK-M1-004` adds versioned tenant notification streams and a Data Plane
consumer conformance implementation. Candidates are fetched by immutable
version, validated, and atomically exchanged in memory; fetch failure retains
the last validated Snapshot. Raw staleness/version telemetry is emitted without
inventing `TBD-016` or `TBD-017` policy defaults.

`TASK-M2-001` publishes the OpenAPI 3.1 contract for
`POST /v1/chat/completions`, versioned compatibility baseline, contract fixtures,
language-neutral Gateway handler binding, and SDK generation-input entrypoint.
Authentication implementation, a custom API-key Header, complete error bodies,
and SDK language remain explicit TBD items. `ADR-001` now supplies the Gateway
server runtime without changing the M2-001 API contract.

`TASK-M2-002` adds a language-neutral Bearer/API Key authentication boundary.
Credential transport is normalized before verification, verified principal data
is the only tenant identity source, and only `authenticated` decisions may
continue to the `TASK-M2-003` authorization boundary. Identity Provider,
custom Header, API-key verification storage/rotation, runtime framework, and
public Error Schema remain explicit TBD/ADR items.

`TASK-M2-003` adds tenant/config-scoped Policy Evaluation and Policy Decision v1
contracts plus a framework-neutral conformance mock. Decisions carry allow,
structured denial reasons, typed obligations, matched policy IDs, policy
version, and trace context. The production policy runtime and indeterminate
resource behavior remain `TBD-004` and `TBD-017`; only explicit `allow` results
can proceed toward `TASK-M2-004` routing.

`TASK-M2-004` adds a Router Plugin v1 registry/composition protocol, structured
plugin results and Route Decisions, compatibility baseline, and mock-plugin
conformance suite. New strategies are registered in a pipeline without adding
strategy branches to the core lifecycle. Method signature, algorithms,
grey-weight semantics, and observation windows remain `TBD-003`/`TBD-014`;
Provider execution remains `TASK-M2-005`.

`TASK-M2-005` adds a Provider-neutral, single-attempt adapter boundary with
tenant/config-scoped runtime bindings, an adapter registry, normalized results,
compatibility baseline, and native/LiteLLM Provider mocks. LiteLLM is limited to
protocol normalization and is not a governance source. The Gateway language is
resolved by `ADR-001` and its DI composition by `ADR-002`; LiteLLM
SDK-versus-Proxy deployment/version and Secret Manager integration remain
`TBD-012`.

`TASK-M2-006` adds a versioned, tenant/config-scoped Retry/Fallback attempt plan,
structured final result, per-attempt telemetry, compatibility baseline, and
Provider failure-injection suite. Every attempt, eligible error kind, fallback
Provider, and delay is explicit. Production attempt limits, timing algorithms,
public failure mapping, and SLO thresholds remain configurable or TBD/ADR.

`TASK-M2-007` adds a versioned `UsageObserved` event, non-blocking Data Plane
enqueue contract, asynchronous publisher/consumer results, compatibility
baseline, and an in-memory end-to-end conformance path from authentication and
Policy through Router, Provider Mock, Retry/Fallback, publication, and an
idempotent Billing consumer. Broker/buffer topology, retry/DLQ, Usage storage,
aggregation, retention, and pricing precision remain explicit TBD/ADR items.

`TASK-M3-001` now has the `ADR-001` .NET 10 Gateway runtime, locked NuGet graph,
digest-pinned multi-stage Linux Dockerfile, numeric non-root user, and executable
health/readiness probes. `test-m3-001` builds and probes the application and
statically validates the image boundary; CI additionally builds and probes the
Linux image. `AC-BLD-001` remains `acceptance=not-met` until `REQ-CICD-004` and
`TASK-CICD-001` select and wire SBOM, scanning, and signing evidence.

`TASK-M3-002` adds a single Gateway Helm chart with development, test, and
production values overlays. Its default renders 3 replicas, port 8080, all
three probes, baseline resources, a PodDisruptionBudget, topology spread,
non-root workload security, and a ClusterIP Service. Production rendering
requires an explicit image digest or tag while `TBD-013` remains open;
namespace/domain/certificate/storage choices remain `TBD-019`. Upgrade and
digest-based rollback are documented without introducing CI direct deployment.

`TASK-M3-003` adds cloud-neutral network, Kubernetes, PostgreSQL, Redis, Kafka,
Object Storage, KMS, and DNS module contracts plus shared dev/stage/prod
composition. It validates tenant/config cache isolation, event-domain
topic/retry/DLQ semantics, independent Data Plane/Runtime node-pool capacity,
encryption references, and the Gateway-to-knowledge-domain boundary without
selecting a cloud or Secret Manager. Provider resources and remote state remain
explicit `TBD-011`/`TBD-012` decisions.

## Versioning and rollback

Git revisions provide source traceability during bootstrap. Published platform
versions must follow SemVer, but whether this monorepo uses one version or
independent component versions is intentionally unresolved under `REQ-REP-006`.
See [docs/versioning.md](docs/versioning.md) and the
[public contract index](docs/contracts/README.md). Bootstrap changes roll back by
source-control revert; they have no data or configuration migration.
