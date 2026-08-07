# PR gate bootstrap

`TASK-M0-003` defines three independent pull-request checks in
`.github/workflows/pr-gates.yml`:

| Job | Repository command | Bootstrap responsibility |
|---|---|---|
| `lint` | `./scripts/task.ps1 lint` | Repository and managed-document lint |
| `test` | `./scripts/task.ps1 test` | Repository, contract-directory, and migration validation |
| `security` | `./scripts/task.ps1 security` | Basic plaintext-credential and private-key pattern checks |

The workflow grants only `contents: read`, does not persist checkout credentials,
does not reference repository secrets, and has no deployment or production
cluster permissions. It must never add direct production `kubectl apply` as a
normal delivery path.

The bootstrap security command is deliberately narrow. It is machine-verifiable
evidence for this task, not the final dependency/image/Secret scanning standard.
The production scanner and policy thresholds remain TBD under `REQ-CICD-002`,
`REQ-CICD-004`, and `TBD-009`; a later task must replace or augment this check
without silently treating its current patterns as complete coverage.

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

The authentication-boundary gate executes framework-neutral Bearer/API Key
conformance scenarios. It verifies that only authenticated decisions carry a
verifier-sourced tenant principal, all failure modes use structured reasons,
credentials are absent from outputs, and unavailable verification never enters
the authorization pipeline.

The Policy Decision gate executes a framework-neutral policy mock over active
tenant, model/region allowlist, projected-budget, tenant-mismatch, version-
mismatch, runtime-unavailable, and typed-obligation scenarios. It verifies that
only explicit allow decisions can approach routing while runtime and
indeterminate handling remain `TBD-004` and `TBD-017`.

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

The Production Image Boundary gate currently validates an explicit
`blocked-tbd-001` state. It rejects an unapproved Dockerfile or hidden runtime,
package-manager, base-image, tool, and evidence selections while preserving all
mandatory image completion controls. Its passing output includes
`acceptance=not-met`; image build, SBOM, scanning, signing, container inspection,
and probe jobs can only replace that state after a reviewed runtime ADR and a
real locked application artifact exist.

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
