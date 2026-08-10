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
| `packages/sdk/contracts/` | Versioned SDK generation pipeline plan and compatibility baseline |
| `deploy/helm/` | Helm charts and values |
| `deploy/images/` | Production image readiness boundaries and approved component Dockerfiles |
| `deploy/kubernetes/` | Native Kubernetes resources and environment overlays |
| `deploy/terraform/` | Infrastructure as code |
| `ops/` | Ownership, SLO, runbook, alerting, and operational assets |
| `docs/` | Architecture, interface, ADR, and development documentation |
| `docs/contracts/` | Versioned public API, event, runtime, and policy contracts |
| `docs/contracts/openapi/openapi.yaml` | Authoritative OpenAPI 3.1 `/v1` contract |
| `docs/contracts/idempotency/` | Versioned, transport-neutral management write idempotency extension point |
| `docs/contracts/pagination/` | Versioned management list pagination candidates and API review boundary |
| `docs/contracts/errors/` | Versioned public HTTP error status semantics without an invented body schema |
| `docs/contracts/policy-decisions/` | Versioned Policy Evaluation and structured decision contracts |
| `docs/contracts/router/` | Versioned Router Plugin registry, result, and decision contracts |
| `docs/contracts/provider-canary/` | Versioned Provider canary policy, observation, and decision contracts |
| `docs/contracts/deprecation/` | Versioned deprecation policy, lifecycle evaluation, and compatibility contracts |
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
the last validated Snapshot. Raw staleness/version telemetry is emitted, and
`TBD-016` now has a versioned policy entry point bound to the existing nullable
`MaximumStalenessSeconds` port. Its production value remains unset, and
threshold-exceeded request behavior remains `TBD-017`.

`TASK-M2-001` publishes the OpenAPI 3.1 contract for
`POST /v1/chat/completions`, versioned compatibility baseline, contract fixtures,
language-neutral Gateway handler binding, and SDK generation-input entrypoint.
Authentication implementation, a custom API-key Header, complete error bodies,
and SDK language remain explicit TBD items. `ADR-001` now supplies the Gateway
server runtime without changing the M2-001 API contract.

`TBD-005` is represented by a versioned management-write idempotency contract
extension point. It normalizes tenant/config/audit context and structured
decisions while deliberately leaving Header name, TTL, storage, response replay,
conflict mapping, and store-failure behavior unresolved until ADR/configuration
review. No management endpoint or production default is invented by this task.

`TBD-006` is represented by a versioned management-list pagination review
boundary. Cursor and offset remain equal candidates; no production strategy,
query parameter names, page-size values, cursor encoding, or consistency model
is selected before API design review. The candidate conformance suite verifies
tenant filtering and continuity without publishing management routes.

`TBD-007` is represented by a versioned SDK generation pipeline boundary.
OpenAPI validation, compatibility checking, input hashing, and planning are
enabled; client generation, generated-client testing, and package publishing are
blocked. No SDK language, generator/version, output layout, or registry has been
selected.

`TBD-008` is represented by a versioned HTTP status-semantics boundary. The
required `400/401/403/429/502` meanings are compatibility-protected while the
public JSON body, field names, code mapping, media type, correlation fields, and
`402` behavior remain unresolved. Structured internal reasons and error
non-disclosure remain mandatory.

`TBD-009` is represented by a configurable PR coverage gate. The production
threshold, metric, aggregation, collector, and report format remain unset. CI
reads `COVERAGE_MINIMUM_PERCENT`; when configured it requires
`COVERAGE_OBSERVED_PERCENT` and enforces the comparison, while an unset threshold
is reported explicitly as not active rather than treated as a coverage pass.

`TBD-010` is represented by a vendor-neutral, target-aware SLI/SLO Dashboard
model and a versioned target-policy configuration schema. Logical indicators
cover request success, p95/p99 latency, time to first token, Provider success,
configuration publish success, and propagation latency. Production objectives,
measurement windows, data-source bindings, alert/burn-rate rules, and release-
gate thresholds remain unconfigured until a reviewed SLO policy publishes them.

`TBD-011` is represented by a versioned cloud-provider selection boundary and a
provider-neutral Terraform gate. Provider identity/source/version, deployment
locations, workload identity, remote state, and all eight capability-adapter
references remain null. The core topology accepts only repository-local modules
and rejects provider/resource/data/backend blocks, `required_providers`, remote
module sources, state files, and vendor identifiers until a reviewed ADR. Future
configuration may publish one or more provider bindings without changing the
shared capability contracts.

`TBD-012` is represented by versioned, tenant/config-scoped opaque `secret_ref`
contracts and a product-neutral Secret Resolver boundary. Secret material is
delivered only in process after tenant, config-version, authorization, and
rotation checks, and never appears in decisions, persistence, logs, telemetry,
errors, or Terraform state. Audit enqueue outcome is structured but asynchronous
and non-blocking. Product/adapter, authentication, reference format, rotation
schedule, caching, lease renewal, and break-glass tooling remain unset.

`TBD-013` is represented by a versioned Image Tag policy entry point and an
immutable publication-record contract. The exact Tag template, components,
normalization, mutable aliases, branch/prerelease behavior, and promotion rules
remain unset. Every releasable image record must bind source repository,
revision, source/release version, OCI labels, build identity, and immutable
digest; production deployment and rollback use the verified digest rather than
treating a Tag as artifact identity.

`TBD-014` is represented by versioned Provider canary policy, observation, and
decision contracts linked from the Router. Exact weights, observation windows,
sample sizes, signals, promotion/rollback thresholds, allocation key/algorithm,
and automatic progression remain unset. The Data Plane consumes a published,
tenant-scoped revision; hard region/compliance filters precede future weighting,
observations are asynchronous, unconfigured or incomplete evaluations hold, and
rollback targets a previously validated revision.

`TBD-015` is represented by versioned deprecation policy and evaluation
contracts covering APIs, model aliases, configuration fields, and capabilities.
A scheduled policy requires explicit window start/end timestamps and retains the
prior contract through the configured end. Duration syntax/value, scheduling
rules, notification channels, post-window enforcement, and exception behavior
remain unset; no current `/v1` operation is marked deprecated.

`TBD-016` is represented by a versioned, tenant/config-scoped Runtime Snapshot
staleness policy. It preserves raw staleness and propagation metrics, requires a
positive value only when explicitly configured, and keeps the default threshold
null. Production maximum seconds and measurement-clock binding remain unset;
crossing a configured threshold does not select a fail-open/fail-closed action.

`TBD-018` is represented by a versioned Ownership Catalog covering every
application and shared package. Required Owner, SLO, Runbook, upgrade-window,
and data-retention fields are machine-verifiable, while organization names,
owner references, and team topology remain unset. Placeholders are explicitly
invalid as production assignments.

`TBD-019` is represented by a versioned production-environment settings schema
and explicit Helm/Terraform inputs for domain, Namespace, certificate issuer,
and StorageClass. Repository Helm values stay empty and Terraform defaults stay
null; test fixtures are never production settings. Publishing and rollback use
reviewed settings revisions without selecting a cloud or deployment product.

`TBD-020` is represented by versioned, product-neutral on-call binding and
production-approval request/decision contracts. Production promotion requires
the complete go-live evidence pack and fails closed while the approval system
is unconfigured or unavailable. Product, schedule, escalation, contact-target,
role, approver-count, separation-of-duty, and outage-procedure bindings remain
unset; coordination lookups are forbidden on the online Data Plane path.

`TASK-M2-002` adds a language-neutral Bearer/API Key authentication boundary.
Credential transport is normalized before verification, verified principal data
is the only tenant identity source, and only `authenticated` decisions may
continue to the `TASK-M2-003` authorization boundary. Identity Provider,
custom Header, API-key verification storage/rotation, runtime framework, and
public Error Schema remain explicit TBD/ADR items.

`TASK-M2-003` adds tenant/config-scoped Policy Evaluation and Policy Decision v1
contracts plus a framework-neutral conformance mock. Decisions carry allow,
structured denial reasons, typed obligations, matched policy IDs, policy
version, and trace context. `ADR-004` selects OPA Data API v1 behind a
replaceable Gateway port; indeterminate resource behavior remains `TBD-017`.
Only explicit `allow` results can proceed toward `TASK-M2-004` routing.

`TASK-M2-004` adds a Router Plugin v1 registry/composition protocol, structured
plugin results and Route Decisions, compatibility baseline, and mock-plugin
conformance suite. New strategies are registered in a pipeline without adding
strategy branches to the core lifecycle. `ADR-003` selects an async,
cancellable method signature; algorithms, grey-weight semantics, and
observation windows remain `TBD-014`. Provider execution remains
`TASK-M2-005`.

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
