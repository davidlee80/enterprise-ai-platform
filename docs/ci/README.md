# PR gate bootstrap

`TASK-M0-003` defines three independent pull-request checks in
`.github/workflows/pr-gates.yml`:

| Job | Repository command | Bootstrap responsibility |
|---|---|---|
| `lint` | `./scripts/task.ps1 lint` | Repository and managed-document lint |
| `test` | `./scripts/linux-smoke.sh`, then `./scripts/task.ps1 test` | Native Bash entrypoint smoke test plus repository, contract, and migration validation |
| `security` | `./scripts/task.ps1 security` | Basic plaintext-credential and private-key pattern checks |

The workflow grants only `contents: read`, does not persist checkout credentials,
does not reference repository secrets, and has no deployment or production
cluster permissions. It must never add direct production `kubectl apply` as a
normal delivery path.

The test job runs on `ubuntu-latest`. Its Bash smoke step requires tracked
executable bits and LF line endings, rejects case-colliding paths, verifies
PowerShell 7 and the CI-pinned .NET/Helm/Terraform versions, and invokes `lint`
plus the CI skeleton test through `scripts/task.sh`. This is executable Linux-host
evidence; subsequent PowerShell steps exercise all task-specific suites on the
same Ubuntu runner.

The bootstrap security command is deliberately narrow. It is machine-verifiable
evidence for this task, not the final dependency/image/Secret scanning standard.
The production scanner and its policy thresholds remain TBD under
`REQ-CICD-004`; a later task must
replace or augment this check without silently treating its current patterns as
complete security coverage.

## Configurable coverage gate

`TBD-009` is implemented as a parameterized CI gate without a production
percentage. The versioned policy and compatibility baseline are
`test-coverage-gate.v1.json` and
`test-coverage-gate-compatibility-baseline.v1.json`.

The workflow maps repository variable `COVERAGE_MINIMUM_PERCENT` into the gate.
A future reviewed collector exports `COVERAGE_OBSERVED_PERCENT` before the gate
step. Behavior is explicit:

- no configured threshold: pass the bootstrap check with
  `COVERAGE_THRESHOLD_TBD_NOT_ENFORCED` and `enforcement=not-active`;
- threshold configured but observation missing/invalid: fail;
- observation below the configured threshold: fail;
- observation at or above the threshold: pass.

Threshold, line/branch metric, aggregation, collector, and report format all
remain null. The conformance suite's `80` values are test-only boundary fixtures,
not a recommended or production threshold. Activating enforcement requires a
reviewed ADR/CI policy and a versioned collector configuration. Rollback restores
the policy and collector together.

## Configurable SLO Dashboard gate

`TBD-010` is implemented as a target-aware Dashboard boundary without production
commitments. The gate validates the logical SLI catalog, versioned target-policy
schema, Dashboard bindings, compatibility baseline, rollback lifecycle, and
telemetry safety. It requires request success, p95/p99 latency, time to first
token, Provider success, configuration publish success, and propagation latency
panels while keeping their data-source and target references unconfigured.

Numeric objectives, measurement windows, error-budget and burn-rate behavior,
alert thresholds, data-source/query bindings, and release-gate failure thresholds
remain `TBD-010`. Activating any of them requires a reviewed, versioned SLO
policy and matching alert/gate configuration; rollback restores the prior set as
one revision.

## Cloud provider neutrality gate

`TBD-011` is implemented as a static provider-neutrality gate plus a versioned
selection schema. It verifies that provider, locations, workload identity,
remote state, and the network/Kubernetes/PostgreSQL/Redis/Kafka/object-storage/
KMS/DNS adapters remain unselected. It also protects the shared capability
contracts and dev/stage/prod composition from premature provider coupling.

The gate runs without Terraform CLI and rejects provider/resource/data/backend
blocks, `required_providers`, non-local module sources, vendor identifiers,
plaintext credential assignments, and committed state or provider lock files.
Selecting a provider requires a reviewed ADR and versioned provider, adapter,
identity, location, and backend set with a compatible rollback revision.

## Secret Manager abstraction gate

`TBD-012` is implemented as opaque `secret_ref` schemas, a versioned product-
neutral binding, safe resolution decisions, and an executable in-memory
resolver. The gate verifies tenant/config isolation, structured Audit enqueue
outcomes, structured resolution reasons, in-process-only credential delivery,
Provider/KMS linkage, break-glass separation, configuration rollback, and
non-blocking asynchronous Audit emission.

Secret Manager product/adapter, authentication, endpoint reference, reference
syntax, rotation schedule and overlap/revocation behavior, credential caching,
lease renewal, and break-glass approval tooling remain null. CI fails if these
are prematurely selected or if a decision/audit artifact exposes `secret_ref`,
credential material, endpoint, raw error, or stack trace.

## Image traceability gate

`TBD-013` is implemented as a versioned Tag-policy entry point plus an immutable
publication record. The gate requires source repository, source revision,
source/release version, build identity, matching OCI labels, and a lowercase
SHA-256 image digest. It rejects missing/placeholder revisions, invalid digests,
and label/record mismatches.

The exact Tag template, components, normalization, mutable-alias rules, branch
and prerelease behavior, and promotion policy remain null. Digest-only release
evidence is valid; a production release Tag remains blocked until it references
a reviewed Tag-policy revision. Rollback selects the previously verified digest
and matching publication record instead of rebuilding a Tag.

## Provider canary configurability gate

`TBD-014` is implemented as versioned policy, observation, decision, boundary,
and compatibility contracts linked to the Router. The gate exercises explicit
hold, promote, and rollback decisions; tenant/config/revision/model isolation;
incomplete windows, insufficient samples, unavailable signals, missing criteria;
and the rule that canary configuration cannot restore a hard-filtered Provider.

Production weights, windows, samples, signals, promotion/rollback thresholds,
allocation key/algorithm, and automatic progression remain null. Fixture values
in the conformance script are test-only. The gate also requires published
snapshot consumption, asynchronous non-blocking observation, structured reasons,
safe metric labels, a revision/rollback target, and preservation of the last
valid snapshot on publication failure.

## Deprecation window configurability gate

`TBD-015` is implemented as versioned policy, lifecycle-evaluation, boundary,
and compatibility contracts covering APIs, model aliases, configuration fields,
and capabilities. The gate verifies start/end ordering, pre-window, active, and
elapsed states, tenant/config/revision/resource isolation, global-policy support,
structured reasons, asynchronous notification, rollback, and OpenAPI linkage.

Production duration and syntax, scheduling rules, notification channels,
post-window enforcement, and exception policy remain null. Fixture timestamps
are test-only. No `/v1` operation may be marked deprecated without a reviewed
policy; removal before the explicit window end remains forbidden.

## Runtime Snapshot staleness configurability gate

`TBD-016` is implemented as a versioned staleness-policy schema, Runtime
Snapshot extension, boundary, compatibility baseline, and executable binding to
the existing nullable `MaximumStalenessSeconds` Consumer port. The gate verifies
tenant/config/revision isolation, positive configured inputs, null defaults,
raw staleness/propagation metrics, rollback metadata, and Redis-failure retention
of the last valid in-memory Snapshot.

The production maximum and measurement-clock reference remain null. Numeric
values in conformance tests are fixtures only. Threshold crossing is observable
but does not change request availability; resource-specific fail-open or
fail-closed behavior remains `TBD-017`.

## Ownership metadata placeholder gate

`TBD-018` is implemented as a versioned catalog, closed record schema, boundary,
compatibility baseline, and executable inventory check for all seven applications
and six shared packages. The gate requires Owner, SLO, Runbook, upgrade-window,
and data-retention metadata fields and rejects missing, duplicate, or unknown
components. Organization names, owner references, and team topology remain null;
the placeholder cannot satisfy production ownership readiness.

## Production environment variable gate

`TBD-019` is implemented as a versioned settings schema and boundary plus
explicit Helm and production Terraform inputs for domain, Namespace,
certificate issuer, and StorageClass. The gate rejects committed production
values, partial settings, Secret fields, cloud-vendor coupling, or missing
rollback metadata. Helm values remain empty and Terraform defaults remain null;
all conformance values are fixtures only.

## On-call and approval interface gate

`TBD-020` is implemented as closed on-call binding and production-approval
request/decision schemas, a product-neutral boundary, compatibility baseline,
and executable fail-closed decision checks. The gate requires all seven go-live
checks and structured evidence references, rejects direct contacts, credentials,
free-form evidence, or online Data Plane coupling, and verifies rollback guards.
Concrete products, schedules, escalation/contact targets, roles, approver count,
separation-of-duty behavior, and outage procedure remain unconfigured.

The test job applies all current migrations to an isolated, empty PostgreSQL
18.4 CI service and verifies the resulting table set. This version is a CI
compatibility sample, not a production PostgreSQL version decision. The service
uses local trust authentication inside the ephemeral runner and publishes no
password or external endpoint; production authentication must never copy this
test-only setting.

After applying all migrations, the same isolated database runs the Outbox
integration test. It verifies enqueue/claim/release/reclaim/ack behavior,
structured failure reasons, at-least-once attempt state, and rollback of a
business write when event insertion violates envelope constraints.

The test job also starts an isolated Redis 8.8.1 service and runs the Snapshot
Store integration suite with the matching official CLI image. The suite verifies
versioned publish/read, compare-and-swap rejection, retained old versions,
rollback, tenant isolation, plaintext-credential-field rejection, and one
tenant-scoped notification per successful transition. The exact
image is a reproducible CI compatibility sample, not a production Redis version,
topology, persistence, eviction, or authentication decision. Test-only unauthenticated
loopback access must not be copied to production.

The same job executes the Data Plane Snapshot Consumer conformance suite. It
uses an in-memory fake version source rather than an external model or Control
Plane database and verifies duplicate/out-of-order notifications, tenant/hash
validation, atomic reference replacement, in-flight reference preservation,
Redis-fetch failure fallback, rollback, and raw version/staleness telemetry.

The OpenAPI 3.1 gate parses the authoritative `/v1` document, resolves local
references, validates request/response/stream fixtures and required HTTP status
semantics, checks the Gateway operation binding, and compares the document with
the committed v1 compatibility baseline. The SDK plan verifies the same source
and hash without choosing a generator or language while `TBD-007` is unresolved.

The admin idempotency gate validates the OpenAPI-linked `TBD-005` extension
point, versioned request/decision/policy schemas, compatibility baseline,
tenant-scoped mock behavior, structured reasons, outbox audit boundary,
rollback metadata, and raw-key non-disclosure. It fails if a Header, TTL,
storage profile, replay/conflict mapping, or store-failure strategy is hard-coded
before an ADR/configuration decision.

The admin pagination gate validates the OpenAPI-linked `TBD-006` review
boundary, versioned query/result/policy schemas, compatibility baseline,
tenant-first filtering, cursor and offset candidate continuity, structured
invalid-position handling, and rollback metadata. It fails if a production
strategy, query parameter name, page-size value, cursor policy, or consistency
behavior is selected before API design review.

The SDK generation gate validates the OpenAPI-linked `TBD-007` pipeline
boundary and compatibility baseline, checks the source version and SHA-256
digest, executes validation/planning, and proves generation, generated-client
testing, and publishing remain blocked. It fails if a language, generator,
output layout, or registry is selected before review.

The public HTTP error gate validates the OpenAPI-linked `TBD-008` status-only
boundary and compatibility baseline. It protects the required
`400/401/403/429/502` meanings, requires structured internal context, checks
non-disclosure, and fails if a public body/content mapping or `402` semantics are
published before API review.

The authentication-boundary gate executes framework-neutral Bearer/API Key
conformance scenarios. It verifies that only authenticated decisions carry a
verifier-sourced tenant principal, all failure modes use structured reasons,
credentials are absent from outputs, and unavailable verification never enters
the authorization pipeline.

The Policy Decision gate executes a framework-neutral policy mock over active
tenant, model/region allowlist, projected-budget, tenant-mismatch, version-
mismatch, runtime-unavailable, and typed-obligation scenarios. It verifies that
only explicit allow decisions can approach routing. Runtime conformance also
verifies the `ADR-004` OPA Data API adapter while indeterminate resource
handling remains `TBD-017`.

The Router Plugin gate executes registry-driven mock composition and proves that
adding a plugin does not modify the core lifecycle. It also covers policy deny,
tenant/config mismatch, missing strategy, plugin unavailability, invalid plugin
output, `force_region`, opaque Provider IDs, and structured decision traces.

The Provider Adapter gate executes native and LiteLLM-shaped in-memory mocks.
It verifies selected-route enforcement, tenant/config/provider binding, registry
resolution, single-attempt behavior, normalized success and failure results,
secret non-disclosure, and the platform-owned Retry/Fallback handoff.
It uses no real Provider endpoint or credential.

The Retry/Fallback gate injects Provider success, timeout, authentication,
rate-limit, invalid-context, and plan failures through in-memory fakes. It
verifies explicit retry/fallback order and delay, non-retryable stop, exhaustion,
tenant/config isolation, failed/final Provider telemetry, high-cardinality label
guards, and secret-free structured results. Test fixture values are not
production timing, attempt-count, or SLO defaults.

The Usage Event gate executes an in-memory authenticated/allowed/routed Provider
Mock path through Retry/Fallback completion, non-blocking enqueue, asynchronous
publish, and idempotent Billing consumption. It proves response release precedes
broker publication and covers queue rejection, broker failure, duplicate event
and business keys, tenant conflicts, body/secret exclusion, and transport/store
TBD guards without connecting to a real broker or Billing database.

The Production Image Boundary gate validates the `ADR-001` .NET 10 runtime,
locked NuGet graph, digest-pinned multi-stage Dockerfile, minimal numeric
non-root runtime, OCI traceability, health contract, and Secret-free build
inputs. The Ubuntu job builds the Gateway, builds the Linux image, inspects its
metadata, and probes `/healthz` and `/readyz`. The gate still reports
`acceptance=not-met`: SBOM generation, scanning, signing, and their acceptance
evidence remain blocked on `REQ-CICD-004` and `TASK-CICD-001`.

The Gateway DDD/DI gate validates `ADR-002`, enforces the compile-time
Domain/Application/Infrastructure/Api dependency graph, restores every project
in locked mode, validates the built-in .NET service container, and proves the
fail-closed Runtime Snapshot port can be replaced by a Fake without duplicate
registration. It does not resolve the remaining plugin method signatures.

The Gateway Helm gate uses Helm v3.21.3 installed by a commit-SHA-pinned setup
action. It lints the chart, renders development/test/production overlays,
asserts the Gateway baseline and workload-safety resources, and negatively
tests missing or ambiguous production image references. It never installs a
release, contacts a cluster, or uses `kubectl apply`.

The Terraform Skeleton gate uses Terraform 1.15.8 installed by a
commit-SHA-pinned setup action. It runs recursive formatting checks and performs
backend-disabled init, validate, and provider-free plan for dev/stage/prod. It
does not authenticate to a cloud, create resources, configure remote state, or
run apply; those actions require reviewed provider, backend, identity, and
approval decisions.

Repository branch protection must mark `lint`, `test`, and `security` as required
checks before merge. That external repository setting cannot be established by
this source-only task and must be verified when the workflow is enabled.

Rollback is a Git revert of the workflow and task-runner changes. This task does
not change runtime configuration, data, images, or deployment state.
