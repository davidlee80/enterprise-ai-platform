[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("lint", "test", "test-m0-002", "test-m0-003", "test-m1-001", "test-m1-002", "test-m1-003", "test-m1-004", "test-m2-001", "test-m2-002", "test-m2-003", "test-m2-004", "test-m2-005", "test-m2-006", "test-m2-007", "test-m3-001", "test-m3-002", "test-m3-003", "security", "build")]
    [string]$Command
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$script:Failures = @()

$applicationNames = @(
    "gateway",
    "iam",
    "billing",
    "provider",
    "policy",
    "router",
    "audit"
)

$packageNames = @(
    "sdk",
    "common",
    "auth",
    "telemetry",
    "db",
    "cache"
)

function Add-Failure {
    param(
        [string]$ReasonCode,
        [string]$Subject,
        [string]$Detail
    )

    $script:Failures += [PSCustomObject]@{
        ReasonCode = $ReasonCode
        Subject = $Subject
        Detail = $Detail
    }
}

function Assert-Directory {
    param([string]$RelativePath)

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        Add-Failure "REPO_DIRECTORY_MISSING" $RelativePath "required directory is absent"
    }
}

function Assert-File {
    param([string]$RelativePath)

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "REPO_FILE_MISSING" $RelativePath "required file is absent"
    }
}

function Assert-FileContains {
    param(
        [string]$RelativePath,
        [string]$ExpectedText,
        [string]$ReasonCode
    )

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "REPO_FILE_MISSING" $RelativePath "cannot inspect missing file"
        return
    }

    $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($content.IndexOf($ExpectedText, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        Add-Failure $ReasonCode $RelativePath ("missing required text: " + $ExpectedText)
    }
}

function Assert-FileNotContains {
    param(
        [string]$RelativePath,
        [string]$ForbiddenText,
        [string]$ReasonCode
    )

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "REPO_FILE_MISSING" $RelativePath "cannot inspect missing file"
        return
    }

    $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($content.IndexOf($ForbiddenText, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        Add-Failure $ReasonCode $RelativePath ("forbidden text found: " + $ForbiddenText)
    }
}

function Get-ManagedReadmes {
    $readmes = @(
        "README.md",
        ".github/workflows/pr-gates.yml",
        "deploy/README.md",
        "deploy/images/README.md",
        "deploy/images/gateway/README.md",
        "deploy/images/gateway/production-image-boundary.v1.json",
        "deploy/images/gateway/production-image.conformance.ps1",
        "deploy/helm/README.md",
        "deploy/helm/gateway/README.md",
        "deploy/helm/gateway/Chart.yaml",
        "deploy/helm/gateway/values.yaml",
        "deploy/helm/gateway/values-dev.yaml",
        "deploy/helm/gateway/values-test.yaml",
        "deploy/helm/gateway/values-prod.yaml",
        "deploy/helm/gateway/values.schema.json",
        "deploy/helm/gateway/templates/_helpers.tpl",
        "deploy/helm/gateway/templates/deployment.yaml",
        "deploy/helm/gateway/templates/service.yaml",
        "deploy/helm/gateway/templates/poddisruptionbudget.yaml",
        "deploy/helm/gateway/gateway-chart.conformance.ps1",
        "deploy/kubernetes/README.md",
        "deploy/terraform/README.md",
        "docs/versioning.md",
        "docs/contracts/README.md",
        "docs/contracts/openapi/README.md",
        "docs/contracts/openapi/openapi.yaml",
        "docs/contracts/openapi/compatibility-baseline.v1.json",
        "docs/contracts/openapi/fixtures/chat-completion.request.valid.json",
        "docs/contracts/openapi/fixtures/chat-completion.request.invalid.json",
        "docs/contracts/openapi/fixtures/chat-completion.response.valid.json",
        "docs/contracts/openapi/fixtures/chat-completion.chunk.valid.json",
        "docs/contracts/events/README.md",
        "docs/contracts/events/usage/README.md",
        "docs/contracts/events/usage/usage-event.v1.schema.json",
        "docs/contracts/events/usage/usage-processing-result.v1.schema.json",
        "docs/contracts/events/usage/usage-event-boundary.v1.json",
        "docs/contracts/events/usage/usage-event-compatibility-baseline.v1.json",
        "docs/contracts/runtime-snapshots/README.md",
        "docs/contracts/runtime-snapshots/runtime-snapshot.v1.schema.json",
        "docs/contracts/runtime-snapshots/snapshot-notification.v1.schema.json",
        "docs/contracts/policy-decisions/README.md",
        "docs/contracts/policy-decisions/policy-evaluation-request.v1.schema.json",
        "docs/contracts/policy-decisions/policy-decision.v1.schema.json",
        "docs/contracts/policy-decisions/policy-boundary.v1.json",
        "docs/contracts/policy-decisions/policy-compatibility-baseline.v1.json",
        "docs/contracts/router/README.md",
        "docs/contracts/router/router-request.v1.schema.json",
        "docs/contracts/router/router-plugin-result.v1.schema.json",
        "docs/contracts/router/route-decision.v1.schema.json",
        "docs/contracts/router/router-registry.v1.schema.json",
        "docs/contracts/router/router-boundary.v1.json",
        "docs/contracts/router/router-compatibility-baseline.v1.json",
        "docs/contracts/providers/README.md",
        "docs/contracts/providers/provider-invocation-request.v1.schema.json",
        "docs/contracts/providers/provider-invocation-result.v1.schema.json",
        "docs/contracts/providers/provider-runtime-config.v1.schema.json",
        "docs/contracts/providers/provider-adapter-registry.v1.schema.json",
        "docs/contracts/providers/provider-adapter-boundary.v1.json",
        "docs/contracts/providers/litellm-runtime-boundary.v1.json",
        "docs/contracts/providers/provider-compatibility-baseline.v1.json",
        "docs/contracts/retry-fallback/README.md",
        "docs/contracts/retry-fallback/retry-fallback-request.v1.schema.json",
        "docs/contracts/retry-fallback/retry-fallback-plan.v1.schema.json",
        "docs/contracts/retry-fallback/retry-fallback-result.v1.schema.json",
        "docs/contracts/retry-fallback/retry-fallback-telemetry.v1.schema.json",
        "docs/contracts/retry-fallback/retry-fallback-boundary.v1.json",
        "docs/contracts/retry-fallback/retry-fallback-compatibility-baseline.v1.json",
        "docs/adr/README.md",
        "docs/ci/README.md",
        "packages/db/migrations/README.md",
        "packages/db/migrations/TBD.md",
        "packages/db/migrations/000001_baseline.up.sql",
        "packages/db/migrations/000002_outbox.up.sql",
        "packages/db/migrations/examples/expand-backfill-contract/README.md",
        "packages/db/migrations/examples/expand-backfill-contract/001-expand.sql.example",
        "packages/db/migrations/examples/expand-backfill-contract/002-backfill.sql.example",
        "packages/db/migrations/examples/expand-backfill-contract/003-contract.sql.example",
        "packages/db/outbox/README.md",
        "packages/db/outbox/transaction.sql.example",
        "packages/db/outbox/outbox.integration.sql",
        "packages/cache/snapshot-store/README.md",
        "packages/cache/snapshot-store/publish.lua",
        "packages/cache/snapshot-store/read-current.lua",
        "packages/cache/snapshot-store/read-version.lua",
        "packages/cache/snapshot-store/rollback.lua",
        "packages/cache/snapshot-store/snapshot-store.integration.ps1",
        "packages/cache/snapshot-consumer/README.md",
        "packages/cache/snapshot-consumer/AtomicSnapshotSlot.cs",
        "packages/cache/snapshot-consumer/SnapshotConsumer.psm1",
        "packages/cache/snapshot-consumer/snapshot-consumer.conformance.ps1",
        "packages/sdk/generate.ps1",
        "packages/auth/contracts/authentication-request.v1.schema.json",
        "packages/auth/contracts/authentication-decision.v1.schema.json",
        "packages/auth/contracts/authentication-boundary.v1.json",
        "packages/auth/authentication-boundary.conformance.ps1",
        "apps/gateway/contracts/chat-completions.binding.v1.json",
        "apps/policy/policy-decision.conformance.ps1",
        "apps/router/router-plugin.conformance.ps1",
        "apps/provider/provider-adapter.conformance.ps1",
        "apps/provider/retry-fallback.conformance.ps1",
        "apps/billing/usage-event.conformance.ps1",
        "docs/contracts/events/event-envelope.v1.schema.json",
        "ops/README.md",
        "ops/ownership/README.md",
        "ops/slo/README.md",
        "ops/runbooks/README.md",
        "scripts/README.md",
        "scripts/openapi.ps1"
    )

    foreach ($name in $applicationNames) {
        $readmes += "apps/$name/README.md"
    }
    foreach ($name in $packageNames) {
        $readmes += "packages/$name/README.md"
    }

    $terraformRoot = Join-Path $repoRoot "deploy/terraform"
    if (Test-Path -LiteralPath $terraformRoot -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $terraformRoot -Recurse -File)) {
            if ($file.FullName -match '[\\/]\.terraform[\\/]' -or
                @(".tf", ".json", ".md", ".ps1") -notcontains $file.Extension.ToLowerInvariant()) {
                continue
            }
            $relativePath = $file.FullName.Substring($repoRoot.Length + 1).Replace("\", "/")
            if ($readmes -notcontains $relativePath) {
                $readmes += $relativePath
            }
        }
    }

    return $readmes
}

function Invoke-Lint {
    foreach ($relativePath in (Get-ManagedReadmes)) {
        Assert-File $relativePath

        $path = Join-Path $repoRoot $relativePath
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            if ($content -match "`t") {
                Add-Failure "MARKDOWN_TAB_FOUND" $relativePath "managed Markdown must not contain tab characters"
            }
            if ($content -match "(?m)[ \t]+$") {
                Add-Failure "MARKDOWN_TRAILING_WHITESPACE" $relativePath "managed Markdown contains trailing whitespace"
            }
        }
    }

    $componentReadmes = @()
    foreach ($name in $applicationNames) {
        $componentReadmes += "apps/$name/README.md"
    }
    foreach ($name in $packageNames) {
        $componentReadmes += "packages/$name/README.md"
    }

    $ownershipFields = @(
        "Owner",
        "SLO",
        "Runbook",
        "Upgrade window",
        "Data retention responsibility",
        "TBD-018",
        "REQ-REP-006"
    )

    foreach ($readme in $componentReadmes) {
        foreach ($field in $ownershipFields) {
            Assert-FileContains $readme $field "OWNER_METADATA_INCOMPLETE"
        }
    }

    Assert-FileContains "packages/common/README.md" "must not contain domain business logic" "COMMON_BOUNDARY_UNEXPLAINED"
}

function Invoke-Test {
    $requiredDirectories = @(
        "apps",
        "packages",
        "deploy",
        "deploy/helm",
        "deploy/kubernetes",
        "deploy/terraform",
        "ops",
        "docs",
        "scripts"
    )

    foreach ($name in $applicationNames) {
        $requiredDirectories += "apps/$name"
    }
    foreach ($name in $packageNames) {
        $requiredDirectories += "packages/$name"
    }
    foreach ($relativePath in $requiredDirectories) {
        Assert-Directory $relativePath
    }

    Assert-FileContains "README.md" "DEVELOPMENT-REQUIREMENTS.md" "ROOT_REQUIREMENTS_LINK_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 lint" "ROOT_LINT_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test" "ROOT_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m0-002" "ROOT_M0_002_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m0-003" "ROOT_M0_003_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m1-001" "ROOT_M1_001_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m1-002" "ROOT_M1_002_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m1-003" "ROOT_M1_003_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m1-004" "ROOT_M1_004_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m2-001" "ROOT_M2_001_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m2-002" "ROOT_M2_002_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m2-003" "ROOT_M2_003_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m2-004" "ROOT_M2_004_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m2-005" "ROOT_M2_005_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m2-006" "ROOT_M2_006_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m2-007" "ROOT_M2_007_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m3-001" "ROOT_M3_001_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m3-002" "ROOT_M3_002_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 test-m3-003" "ROOT_M3_003_TEST_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 security" "ROOT_SECURITY_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\migration.ps1 validate" "ROOT_MIGRATION_VALIDATE_ENTRY_MISSING"
    Assert-FileContains "README.md" "scripts\task.ps1 build" "ROOT_BUILD_ENTRY_MISSING"
    Assert-FileContains "README.md" "stable APIs or versioned events" "CROSS_DOMAIN_BOUNDARY_MISSING"
    Assert-FileContains "docs/versioning.md" "Git revision" "SOURCE_TRACEABILITY_MISSING"
    Assert-FileContains "docs/versioning.md" "unified version or independently versioned" "VERSION_TBD_MISSING"

    Invoke-ContractDirectoryTest
    Invoke-CISkeletonTest
    Invoke-MigrationTest
    Invoke-OutboxTest
    Invoke-SnapshotStoreTest
    Invoke-SnapshotConsumerTest
    Invoke-OpenApiContractTest
    Invoke-AuthenticationBoundaryTest
    Invoke-PolicyDecisionTest
    Invoke-RouterPluginTest
    Invoke-ProviderAdapterTest
    Invoke-RetryFallbackTest
    Invoke-UsageEventTest
    Invoke-ProductionImageTest
    Invoke-GatewayHelmTest
    Invoke-TerraformSkeletonTest
}

function Invoke-ContractDirectoryTest {
    $contractDirectories = @(
        "docs/contracts",
        "docs/contracts/openapi",
        "docs/contracts/events",
        "docs/contracts/events/usage",
        "docs/contracts/runtime-snapshots",
        "docs/contracts/policy-decisions",
        "docs/contracts/router",
        "docs/contracts/providers",
        "docs/contracts/retry-fallback",
        "docs/adr"
    )

    foreach ($relativePath in $contractDirectories) {
        Assert-Directory $relativePath
        Assert-File ("$relativePath/README.md")
    }

    Assert-FileContains "docs/contracts/README.md" "OpenAPI" "CONTRACT_INDEX_OPENAPI_MISSING"
    Assert-FileContains "docs/contracts/README.md" "Event schemas" "CONTRACT_INDEX_EVENT_MISSING"
    Assert-FileContains "docs/contracts/README.md" "Usage Event schemas" "CONTRACT_INDEX_USAGE_EVENT_MISSING"
    Assert-FileContains "docs/contracts/README.md" "Runtime Snapshot schemas" "CONTRACT_INDEX_SNAPSHOT_MISSING"
    Assert-FileContains "docs/contracts/README.md" "Policy Decision schemas" "CONTRACT_INDEX_POLICY_MISSING"
    Assert-FileContains "docs/contracts/README.md" "Router Plugin schemas" "CONTRACT_INDEX_ROUTER_MISSING"
    Assert-FileContains "docs/contracts/README.md" "Provider Adapter schemas" "CONTRACT_INDEX_PROVIDER_MISSING"
    Assert-FileContains "docs/contracts/README.md" "Retry/Fallback schemas" "CONTRACT_INDEX_RETRY_FALLBACK_MISSING"
    Assert-FileContains "docs/contracts/README.md" "Architecture decisions" "CONTRACT_INDEX_ADR_MISSING"
    Assert-FileContains "docs/contracts/README.md" "does not publish a contract" "PLACEHOLDER_AUTHORITY_UNCLEAR"

    Assert-FileContains "docs/contracts/openapi/README.md" "OpenAPI 3.1" "OPENAPI_VERSION_REQUIREMENT_MISSING"
    Assert-FileContains "docs/contracts/openapi/README.md" "TBD-008" "OPENAPI_ERROR_SCHEMA_TBD_MISSING"
    Assert-FileContains "docs/contracts/events/README.md" "schema_version" "EVENT_SCHEMA_VERSION_MISSING"
    Assert-FileContains "docs/contracts/events/README.md" "duplicate delivery" "EVENT_IDEMPOTENCY_MISSING"
    Assert-FileContains "docs/contracts/runtime-snapshots/README.md" "TBD-016" "SNAPSHOT_STALENESS_TBD_MISSING"
    Assert-FileContains "docs/contracts/runtime-snapshots/README.md" "last valid snapshot" "SNAPSHOT_ROLLBACK_MISSING"
    Assert-FileContains "docs/contracts/policy-decisions/README.md" "denial reason" "POLICY_REASON_MISSING"
    Assert-FileContains "docs/contracts/policy-decisions/README.md" "TBD-004" "POLICY_RUNTIME_TBD_MISSING"
    Assert-FileContains "docs/adr/README.md" "REQ-*" "ADR_TRACEABILITY_MISSING"
    Assert-FileContains "docs/adr/README.md" "rollback or replacement path" "ADR_ROLLBACK_MISSING"
}

function Invoke-CISkeletonTest {
    $workflow = ".github/workflows/pr-gates.yml"

    Assert-Directory ".github/workflows"
    Assert-File $workflow
    Assert-File "docs/ci/README.md"

    Assert-FileContains $workflow "pull_request:" "CI_PULL_REQUEST_TRIGGER_MISSING"
    Assert-FileContains $workflow "contents: read" "CI_LEAST_PRIVILEGE_MISSING"
    Assert-FileContains $workflow "actions/checkout@v6.0.2" "CI_CHECKOUT_VERSION_MISSING"
    Assert-FileContains $workflow "persist-credentials: false" "CI_CREDENTIAL_PERSISTENCE_UNSAFE"
    Assert-FileContains $workflow "  lint:" "CI_LINT_JOB_MISSING"
    Assert-FileContains $workflow "  test:" "CI_TEST_JOB_MISSING"
    Assert-FileContains $workflow "  security:" "CI_SECURITY_JOB_MISSING"
    Assert-FileContains $workflow "./scripts/task.ps1 lint" "CI_LINT_COMMAND_MISSING"
    Assert-FileContains $workflow "./scripts/task.ps1 test" "CI_TEST_COMMAND_MISSING"
    Assert-FileContains $workflow "./scripts/task.ps1 security" "CI_SECURITY_COMMAND_MISSING"

    Assert-FileNotContains $workflow "kubectl apply" "CI_DIRECT_PRODUCTION_DEPLOY_FORBIDDEN"
    Assert-FileNotContains $workflow "secrets." "CI_SECRET_REFERENCE_FORBIDDEN"
    Assert-FileNotContains $workflow "contents: write" "CI_WRITE_PERMISSION_FORBIDDEN"
    Assert-FileNotContains $workflow "write-all" "CI_WRITE_ALL_PERMISSION_FORBIDDEN"
    Assert-FileNotContains $workflow "  push:" "CI_NON_PR_TRIGGER_FORBIDDEN"

    $workflowPath = Join-Path $repoRoot $workflow
    if (Test-Path -LiteralPath $workflowPath -PathType Leaf) {
        $workflowContent = Get-Content -LiteralPath $workflowPath -Raw -Encoding UTF8
        $checkoutCount = [regex]::Matches($workflowContent, "(?m)^\s*uses: actions/checkout@v6\.0\.2\s*$").Count
        $credentialSettingCount = [regex]::Matches($workflowContent, "(?m)^\s*persist-credentials: false\s*$").Count
        if ($checkoutCount -ne 3 -or $credentialSettingCount -ne 3) {
            Add-Failure "CI_CHECKOUT_HARDENING_INCOMPLETE" $workflow "all three jobs must use the pinned checkout action without persisted credentials"
        }
    }

    Assert-FileContains "docs/ci/README.md" "remain TBD" "CI_SECURITY_SCANNER_TBD_MISSING"
    Assert-FileContains "docs/ci/README.md" "branch protection" "CI_REQUIRED_CHECK_SETUP_MISSING"
    Assert-FileContains "docs/ci/README.md" "Git revert" "CI_ROLLBACK_MISSING"
}

function Invoke-Security {
    $files = @(& git -C $repoRoot ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "SECURITY_FILE_ENUMERATION_FAILED" $repoRoot "git could not enumerate repository files"
        return
    }

    $credentialAssignmentPattern = '(?i)(api[_-]?key|provider[_-]?key|secret|token)\s*[:=]\s*["''][A-Za-z0-9_\-]{12,}["'']'
    $privateKeyPattern = '-----BEGIN(?: [A-Z0-9]+)? PRIVATE KEY-----'

    foreach ($relativePath in $files) {
        $path = Join-Path $repoRoot $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ($content -match $credentialAssignmentPattern) {
            Add-Failure "PLAINTEXT_CREDENTIAL_PATTERN" $relativePath "possible plaintext credential assignment detected"
        }
        if ($content -match $privateKeyPattern) {
            Add-Failure "PRIVATE_KEY_MATERIAL_PATTERN" $relativePath "possible private key material detected"
        }
    }
}

function Invoke-MigrationTest {
    $migrationRunner = Join-Path $PSScriptRoot "migration.ps1"
    Assert-File "scripts/migration.ps1"
    Assert-File "packages/db/migrations/000001_baseline.up.sql"
    Assert-File "packages/db/migrations/TBD.md"
    Assert-File "packages/db/migrations/examples/expand-backfill-contract/README.md"

    if (Test-Path -LiteralPath $migrationRunner -PathType Leaf) {
        $validationOutput = @(& $migrationRunner validate)
        $validationExitCode = $LASTEXITCODE
        foreach ($line in $validationOutput) {
            Write-Output $line
        }
        if ($validationExitCode -ne 0) {
            Add-Failure "MIGRATION_VALIDATION_FAILED" "scripts/migration.ps1" "migration static validation returned a failure"
        }
    }

    $workflow = ".github/workflows/pr-gates.yml"
    Assert-FileContains $workflow "postgres:18.4-trixie" "CI_POSTGRES_SERVICE_MISSING"
    Assert-FileContains $workflow "Migration static validation" "CI_MIGRATION_VALIDATION_MISSING"
    Assert-FileContains $workflow "Empty database migration" "CI_EMPTY_DATABASE_TEST_MISSING"
    Assert-FileContains $workflow "EMPTY_DATABASE_MIGRATION_OK" "CI_SCHEMA_EVIDENCE_MISSING"
    Assert-FileContains $workflow "MIGRATION_FAILURE_ROLLBACK_OK" "CI_MIGRATION_FAILURE_TEST_MISSING"
    Assert-FileNotContains $workflow "POSTGRES_PASSWORD" "CI_DATABASE_PASSWORD_FORBIDDEN"
    Assert-FileNotContains $workflow "PGPASSWORD" "CI_DATABASE_PASSWORD_FORBIDDEN"

    Assert-FileContains "packages/db/migrations/README.md" "forward-only" "MIGRATION_FORWARD_POLICY_MISSING"
    Assert-FileContains "packages/db/migrations/README.md" "Production rollback" "MIGRATION_ROLLBACK_POLICY_MISSING"
    Assert-FileContains "packages/db/migrations/README.md" "remain TBD" "MIGRATION_TOOL_TBD_MISSING"
    Assert-FileContains "packages/db/migrations/TBD.md" "None of these placeholders authorizes an empty table" "UNCONFIRMED_SCHEMA_GUARD_MISSING"
}

function Invoke-OutboxTest {
    $outboxMigration = "packages/db/migrations/000002_outbox.up.sql"
    $eventSchema = "docs/contracts/events/event-envelope.v1.schema.json"
    $integrationTest = "packages/db/outbox/outbox.integration.sql"

    Assert-File $outboxMigration
    Assert-File $eventSchema
    Assert-File "packages/db/outbox/README.md"
    Assert-File "packages/db/outbox/transaction.sql.example"
    Assert-File $integrationTest

    foreach ($requiredText in @(
        "CREATE TABLE outbox_event",
        "event_id UUID PRIMARY KEY",
        "tenant_id UUID REFERENCES tenant(id)",
        "CREATE FUNCTION enqueue_outbox_event",
        "CREATE FUNCTION claim_outbox_events",
        "FOR UPDATE SKIP LOCKED",
        "CREATE FUNCTION mark_outbox_event_published",
        "CREATE FUNCTION release_outbox_event",
        "last_reason_code TEXT",
        "REVOKE ALL ON FUNCTION enqueue_outbox_event",
        "REVOKE ALL ON FUNCTION claim_outbox_events",
        "REVOKE ALL ON FUNCTION mark_outbox_event_published",
        "REVOKE ALL ON FUNCTION release_outbox_event"
    )) {
        Assert-FileContains $outboxMigration $requiredText "OUTBOX_MIGRATION_INCOMPLETE"
    }
    Assert-FileNotContains $outboxMigration "DROP TABLE" "OUTBOX_DESTRUCTIVE_MIGRATION_FORBIDDEN"
    Assert-FileNotContains $outboxMigration "provider_key" "OUTBOX_PROVIDER_KEY_FORBIDDEN"

    Assert-FileContains "packages/db/outbox/transaction.sql.example" "BEGIN;" "OUTBOX_TRANSACTION_BEGIN_MISSING"
    Assert-FileContains "packages/db/outbox/transaction.sql.example" "enqueue_outbox_event" "OUTBOX_TRANSACTION_ENQUEUE_MISSING"
    Assert-FileContains "packages/db/outbox/transaction.sql.example" "COMMIT;" "OUTBOX_TRANSACTION_COMMIT_MISSING"

    Assert-FileContains "packages/db/outbox/README.md" "at-least-once" "OUTBOX_DELIVERY_SEMANTICS_MISSING"
    Assert-FileContains "packages/db/outbox/README.md" 'deduplicate by `event_id`' "OUTBOX_IDEMPOTENCY_MISSING"
    Assert-FileContains "packages/db/outbox/README.md" "reason_code" "OUTBOX_REASON_CODE_MISSING"
    Assert-FileContains "packages/db/outbox/README.md" "No production value is hard-coded" "OUTBOX_TBD_GUARD_MISSING"
    Assert-FileContains "packages/db/outbox/README.md" "Payload logging is disabled" "OUTBOX_PAYLOAD_LOGGING_GUARD_MISSING"

    Assert-FileContains $integrationTest "OUTBOX_ATOMIC_ROLLBACK_FAILED" "OUTBOX_ATOMICITY_TEST_MISSING"
    Assert-FileContains $integrationTest "BROKER_UNAVAILABLE" "OUTBOX_FAILURE_REASON_TEST_MISSING"
    Assert-FileContains $integrationTest "attempt_count = 2" "OUTBOX_REDELIVERY_TEST_MISSING"

    $eventSchemaPath = Join-Path $repoRoot $eventSchema
    if (Test-Path -LiteralPath $eventSchemaPath -PathType Leaf) {
        try {
            $schema = Get-Content -LiteralPath $eventSchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $requiredFields = @($schema.required)
            foreach ($field in @("event_id", "event_type", "schema_version", "occurred_at", "tenant_id", "producer", "payload")) {
                if ($requiredFields -notcontains $field) {
                    Add-Failure "EVENT_ENVELOPE_FIELD_MISSING" $eventSchema ("required field is absent: " + $field)
                }
            }
            if ($requiredFields -contains "request_id" -or $requiredFields -contains "trace_id") {
                Add-Failure "EVENT_OPTIONAL_CORRELATION_REQUIRED" $eventSchema "request_id and trace_id must remain optional"
            }
            if ($schema.properties.schema_version.minimum -ne 1) {
                Add-Failure "EVENT_SCHEMA_VERSION_INVALID" $eventSchema "schema_version minimum must be 1"
            }
            if ($schema.additionalProperties -ne $false) {
                Add-Failure "EVENT_ENVELOPE_EXTENSION_UNVERSIONED" $eventSchema "v1 envelope must reject unversioned top-level fields"
            }
        }
        catch {
            Add-Failure "EVENT_SCHEMA_JSON_INVALID" $eventSchema $_.Exception.Message
        }
    }

    Assert-FileContains "docs/contracts/events/README.md" "event-envelope.v1.schema.json" "EVENT_SCHEMA_INDEX_MISSING"
    Assert-FileContains ".github/workflows/pr-gates.yml" "outbox.integration.sql" "CI_OUTBOX_TEST_MISSING"
    Assert-FileContains ".github/workflows/pr-gates.yml" "OUTBOX_INTEGRATION_OK" "CI_OUTBOX_EVIDENCE_MISSING"
}

function Invoke-SnapshotStoreTest {
    $schemaFile = "docs/contracts/runtime-snapshots/runtime-snapshot.v1.schema.json"
    $storeReadme = "packages/cache/snapshot-store/README.md"
    $publishScript = "packages/cache/snapshot-store/publish.lua"
    $readCurrentScript = "packages/cache/snapshot-store/read-current.lua"
    $readVersionScript = "packages/cache/snapshot-store/read-version.lua"
    $rollbackScript = "packages/cache/snapshot-store/rollback.lua"
    $integrationTest = "packages/cache/snapshot-store/snapshot-store.integration.ps1"
    $workflow = ".github/workflows/pr-gates.yml"

    foreach ($file in @(
        $schemaFile,
        $storeReadme,
        $publishScript,
        $readCurrentScript,
        $readVersionScript,
        $rollbackScript,
        $integrationTest
    )) {
        Assert-File $file
    }

    $schemaPath = Join-Path $repoRoot $schemaFile
    if (Test-Path -LiteralPath $schemaPath -PathType Leaf) {
        try {
            $schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $requiredFields = @($schema.required)
            foreach ($field in @("config_version", "tenant_id", "model_alias", "policy_ids", "route_strategy", "providers")) {
                if ($requiredFields -notcontains $field) {
                    Add-Failure "SNAPSHOT_SCHEMA_FIELD_MISSING" $schemaFile ("required field is absent: " + $field)
                }
            }
            if ($schema.properties.config_version.minimum -ne 1) {
                Add-Failure "SNAPSHOT_SCHEMA_VERSION_INVALID" $schemaFile "config_version minimum must be 1"
            }
            if ($schema.properties.providers.minItems -ne 1) {
                Add-Failure "SNAPSHOT_SCHEMA_PROVIDER_SET_EMPTY" $schemaFile "at least one candidate Provider is required"
            }
            if ($schema.additionalProperties -ne $true) {
                Add-Failure "SNAPSHOT_SCHEMA_NOT_EXTENSIBLE" $schemaFile "REQ-GEN-009 permits additive Snapshot fields"
            }
        }
        catch {
            Add-Failure "SNAPSHOT_SCHEMA_JSON_INVALID" $schemaFile $_.Exception.Message
        }
    }

    foreach ($requiredText in @(
        "runtime-snapshot:{",
        "expected_current_version",
        "content_hash",
        "SNAPSHOT_CURRENT_VERSION_CONFLICT",
        "SNAPSHOT_VERSION_CONFLICT",
        "SNAPSHOT_PLAINTEXT_CREDENTIAL_FIELD_FORBIDDEN",
        "SNAPSHOT_PUBLISHED"
    )) {
        Assert-FileContains $publishScript $requiredText "SNAPSHOT_PUBLISH_BOUNDARY_INCOMPLETE"
    }
    Assert-FileContains $readCurrentScript "SNAPSHOT_CURRENT_READ" "SNAPSHOT_CURRENT_READ_MISSING"
    Assert-FileContains $readVersionScript "SNAPSHOT_VERSION_READ" "SNAPSHOT_VERSION_READ_MISSING"
    Assert-FileContains $rollbackScript "SNAPSHOT_ROLLED_BACK" "SNAPSHOT_ROLLBACK_MISSING"
    Assert-FileContains $rollbackScript '"transition_reason", "ROLLBACK"' "SNAPSHOT_ROLLBACK_REASON_MISSING"

    foreach ($script in @($publishScript, $readCurrentScript, $readVersionScript, $rollbackScript)) {
        Assert-FileNotContains $script 'redis.call("DEL"' "SNAPSHOT_VERSION_DELETE_FORBIDDEN"
        Assert-FileNotContains $script 'redis.call("EXPIRE"' "SNAPSHOT_TTL_HARDCODE_FORBIDDEN"
        Assert-FileNotContains $script 'redis.call("FLUSH' "SNAPSHOT_BROAD_DELETE_FORBIDDEN"
    }

    Assert-FileContains $storeReadme "PostgreSQL and the Control Plane remain the system of record" "SNAPSHOT_TRUTH_SOURCE_UNCLEAR"
    Assert-FileContains $storeReadme "must not fall back" "SNAPSHOT_DP_DATABASE_FALLBACK_FORBIDDEN"
    Assert-FileContains $storeReadme "TASK-M1-004" "SNAPSHOT_CONSUMER_SCOPE_UNCLEAR"
    Assert-FileContains $storeReadme "TBD-016" "SNAPSHOT_STALENESS_TBD_MISSING"
    Assert-FileContains $storeReadme "TBD-017" "SNAPSHOT_FAILURE_POLICY_TBD_MISSING"
    Assert-FileContains $storeReadme 'no `EXPIRE`' "SNAPSHOT_RETENTION_UNDECIDED_GUARD_MISSING"

    foreach ($evidence in @(
        "SNAPSHOT_CURRENT_VERSION_CONFLICT",
        "SNAPSHOT_VERSION_CONFLICT",
        "SNAPSHOT_PLAINTEXT_CREDENTIAL_FIELD_FORBIDDEN",
        "SNAPSHOT_TENANT_KEY_MISMATCH",
        "SNAPSHOT_ROLLED_BACK",
        "REDIS_SNAPSHOT_STORE_INTEGRATION_OK"
    )) {
        Assert-FileContains $integrationTest $evidence "SNAPSHOT_INTEGRATION_SCENARIO_MISSING"
    }

    Assert-FileContains $workflow "redis:8.8.1-trixie" "CI_REDIS_SERVICE_MISSING"
    Assert-FileContains $workflow "Verify Redis Snapshot Store" "CI_SNAPSHOT_TEST_MISSING"
    Assert-FileContains $workflow "snapshot-store.integration.ps1" "CI_SNAPSHOT_TEST_COMMAND_MISSING"
    Assert-FileContains "docs/ci/README.md" "not a production Redis version" "CI_REDIS_VERSION_BOUNDARY_MISSING"
}

function Invoke-SnapshotConsumerTest {
    $notificationSchema = "docs/contracts/runtime-snapshots/snapshot-notification.v1.schema.json"
    $consumerReadme = "packages/cache/snapshot-consumer/README.md"
    $atomicSlot = "packages/cache/snapshot-consumer/AtomicSnapshotSlot.cs"
    $consumerModule = "packages/cache/snapshot-consumer/SnapshotConsumer.psm1"
    $conformanceTest = "packages/cache/snapshot-consumer/snapshot-consumer.conformance.ps1"
    $publishScript = "packages/cache/snapshot-store/publish.lua"
    $rollbackScript = "packages/cache/snapshot-store/rollback.lua"
    $workflow = ".github/workflows/pr-gates.yml"

    foreach ($file in @($notificationSchema, $consumerReadme, $atomicSlot, $consumerModule, $conformanceTest)) {
        Assert-File $file
    }

    $schemaPath = Join-Path $repoRoot $notificationSchema
    if (Test-Path -LiteralPath $schemaPath -PathType Leaf) {
        try {
            $schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $requiredFields = @($schema.required)
            foreach ($field in @(
                "schema_version",
                "notification_id",
                "tenant_id",
                "config_version",
                "content_hash",
                "activated_at",
                "transition_reason"
            )) {
                if ($requiredFields -notcontains $field) {
                    Add-Failure "SNAPSHOT_NOTIFICATION_FIELD_MISSING" $notificationSchema ("required field is absent: " + $field)
                }
            }
            if ($schema.properties.schema_version.const -ne 1) {
                Add-Failure "SNAPSHOT_NOTIFICATION_VERSION_INVALID" $notificationSchema "schema_version must be fixed at 1"
            }
            if ($schema.additionalProperties -ne $false) {
                Add-Failure "SNAPSHOT_NOTIFICATION_UNVERSIONED_EXTENSION" $notificationSchema "v1 notification must reject unversioned fields"
            }
        }
        catch {
            Add-Failure "SNAPSHOT_NOTIFICATION_SCHEMA_INVALID" $notificationSchema $_.Exception.Message
        }
    }

    foreach ($script in @($publishScript, $rollbackScript)) {
        Assert-FileContains $script "runtime-snapshot:{" "SNAPSHOT_NOTIFICATION_TENANT_KEY_MISSING"
        Assert-FileContains $script 'redis.call("XADD"' "SNAPSHOT_NOTIFICATION_WRITE_MISSING"
        Assert-FileContains $script '"notification_id", notification_id' "SNAPSHOT_NOTIFICATION_ID_MISSING"
        Assert-FileNotContains $script "MAXLEN" "SNAPSHOT_STREAM_RETENTION_HARDCODE_FORBIDDEN"
        Assert-FileNotContains $script 'redis.call("EXPIRE"' "SNAPSHOT_STREAM_TTL_HARDCODE_FORBIDDEN"

        $scriptPath = Join-Path $repoRoot $script
        if (Test-Path -LiteralPath $scriptPath -PathType Leaf) {
            $scriptContent = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
            $notificationWrite = $scriptContent.IndexOf('redis.call("XADD"', [System.StringComparison]::Ordinal)
            $pointerWrite = $scriptContent.LastIndexOf('redis.call("HSET", KEYS[2]', [System.StringComparison]::Ordinal)
            if ($notificationWrite -lt 0 -or $pointerWrite -lt $notificationWrite) {
                Add-Failure "SNAPSHOT_POINTER_NOT_FINAL_WRITE" $script "current pointer must remain the final publication-state write"
            }
        }
    }

    Assert-FileContains $atomicSlot "Interlocked.CompareExchange" "SNAPSHOT_ATOMIC_CAPTURE_MISSING"
    Assert-FileContains $atomicSlot "Interlocked.Exchange" "SNAPSHOT_ATOMIC_SWAP_MISSING"
    foreach ($reasonCode in @(
        "SNAPSHOT_NOTIFICATION_DUPLICATE",
        "SNAPSHOT_NOTIFICATION_STALE",
        "SNAPSHOT_NOTIFICATION_NOT_CURRENT",
        "SNAPSHOT_ROLLBACK_ORDER_INVALID",
        "SNAPSHOT_FETCH_FAILED",
        "SNAPSHOT_STORED_METADATA_INVALID",
        "SNAPSHOT_CORE_FIELDS_INVALID",
        "SNAPSHOT_ATOMIC_SWAP_APPLIED",
        "SNAPSHOT_NOT_LOADED",
        "SNAPSHOT_CURRENT_READ_FAILED",
        "SNAPSHOT_METRICS_SAMPLED"
    )) {
        Assert-FileContains $consumerModule $reasonCode "SNAPSHOT_CONSUMER_REASON_CODE_MISSING"
    }
    Assert-FileContains $consumerModule "active_config_version" "SNAPSHOT_ACTIVE_VERSION_METRIC_MISSING"
    Assert-FileContains $consumerModule "staleness_seconds" "SNAPSHOT_STALENESS_METRIC_MISSING"
    Assert-FileContains $consumerModule "propagation_latency_seconds" "SNAPSHOT_PROPAGATION_METRIC_MISSING"
    Assert-FileContains $consumerModule "Sync-RuntimeSnapshotCurrent" "SNAPSHOT_RECONNECT_RECONCILIATION_MISSING"
    Assert-FileNotContains $consumerModule "Npgsql" "SNAPSHOT_CONTROL_PLANE_DATABASE_DEPENDENCY_FORBIDDEN"
    Assert-FileNotContains $consumerModule "packages/db" "SNAPSHOT_CONTROL_PLANE_DATABASE_DEPENDENCY_FORBIDDEN"

    Assert-FileContains $consumerReadme "at-least-once" "SNAPSHOT_NOTIFICATION_DELIVERY_UNCLEAR"
    Assert-FileContains $consumerReadme "must reconcile the current pointer" "SNAPSHOT_RECONNECT_RECONCILIATION_MISSING"
    Assert-FileContains $consumerReadme "last validated" "SNAPSHOT_REDIS_OUTAGE_FALLBACK_MISSING"
    Assert-FileContains $consumerReadme "must never perform a synchronous PostgreSQL fallback" "SNAPSHOT_DATABASE_FALLBACK_FORBIDDEN"
    Assert-FileContains $consumerReadme "TBD-016" "SNAPSHOT_STALENESS_TBD_MISSING"
    Assert-FileContains $consumerReadme "TBD-017" "SNAPSHOT_FAILURE_POLICY_TBD_MISSING"
    Assert-FileContains $consumerReadme "does not select the backend language" "SNAPSHOT_RUNTIME_LANGUAGE_TBD_MISSING"
    Assert-FileContains $consumerReadme "requires an ADR" "SNAPSHOT_INFLIGHT_ADR_GUARD_MISSING"

    foreach ($evidence in @(
        "SNAPSHOT_ATOMIC_SWAP_APPLIED",
        "SNAPSHOT_NOTIFICATION_DUPLICATE",
        "SNAPSHOT_NOTIFICATION_STALE",
        "SNAPSHOT_NOTIFICATION_NOT_CURRENT",
        "SNAPSHOT_ROLLBACK_ORDER_INVALID",
        "SNAPSHOT_FETCH_FAILED",
        "SNAPSHOT_STORED_METADATA_INVALID",
        "SNAPSHOT_NOT_LOADED",
        "SNAPSHOT_CURRENT_READ_FAILED",
        "DATA_PLANE_SNAPSHOT_CONSUMER_CONFORMANCE_OK"
    )) {
        Assert-FileContains $conformanceTest $evidence "SNAPSHOT_CONSUMER_SCENARIO_MISSING"
    }

    $conformancePath = Join-Path $repoRoot $conformanceTest
    if (Test-Path -LiteralPath $conformancePath -PathType Leaf) {
        try {
            $output = @(& $conformancePath)
            foreach ($line in $output) {
                Write-Output $line
            }
            if ($output -notcontains "status=pass reason_code=DATA_PLANE_SNAPSHOT_CONSUMER_CONFORMANCE_OK") {
                Add-Failure "SNAPSHOT_CONSUMER_CONFORMANCE_FAILED" $conformanceTest "success evidence was not emitted"
            }
        }
        catch {
            Add-Failure "SNAPSHOT_CONSUMER_CONFORMANCE_FAILED" $conformanceTest $_.Exception.Message
        }
    }

    Assert-FileContains $workflow "Verify Data Plane Snapshot Consumer" "CI_SNAPSHOT_CONSUMER_TEST_MISSING"
    Assert-FileContains $workflow "test-m1-004" "CI_SNAPSHOT_CONSUMER_COMMAND_MISSING"
}

function Invoke-OpenApiContractTest {
    $contract = "docs/contracts/openapi/openapi.yaml"
    $contractReadme = "docs/contracts/openapi/README.md"
    $baseline = "docs/contracts/openapi/compatibility-baseline.v1.json"
    $binding = "apps/gateway/contracts/chat-completions.binding.v1.json"
    $openApiRunner = "scripts/openapi.ps1"
    $sdkRunner = "packages/sdk/generate.ps1"
    $workflow = ".github/workflows/pr-gates.yml"

    foreach ($file in @(
        $contract,
        $contractReadme,
        $baseline,
        $binding,
        $openApiRunner,
        $sdkRunner,
        "docs/contracts/openapi/fixtures/chat-completion.request.valid.json",
        "docs/contracts/openapi/fixtures/chat-completion.request.invalid.json",
        "docs/contracts/openapi/fixtures/chat-completion.response.valid.json",
        "docs/contracts/openapi/fixtures/chat-completion.chunk.valid.json"
    )) {
        Assert-File $file
    }

    $runnerPath = Join-Path $repoRoot $openApiRunner
    if (Test-Path -LiteralPath $runnerPath -PathType Leaf) {
        foreach ($validation in @(
            [PSCustomObject]@{ Command = "validate"; Evidence = "status=pass command=validate reason_code=OPENAPI_3_1_CONTRACT_OK" },
            [PSCustomObject]@{ Command = "compatibility"; Evidence = "status=pass command=compatibility reason_code=OPENAPI_V1_COMPATIBILITY_OK" }
        )) {
            try {
                $output = @(& $runnerPath $validation.Command)
                foreach ($line in $output) {
                    Write-Output $line
                }
                if ($output -notcontains $validation.Evidence) {
                    Add-Failure "OPENAPI_EXECUTABLE_VALIDATION_FAILED" $openApiRunner ("success evidence was not emitted for " + $validation.Command)
                }
            }
            catch {
                Add-Failure "OPENAPI_EXECUTABLE_VALIDATION_FAILED" $openApiRunner $_.Exception.Message
            }
        }
    }

    $sdkPath = Join-Path $repoRoot $sdkRunner
    if (Test-Path -LiteralPath $sdkPath -PathType Leaf) {
        try {
            $sdkOutput = @(& $sdkPath plan)
            foreach ($line in $sdkOutput) {
                Write-Output $line
            }
            if ($sdkOutput -notcontains "status=pass command=plan reason_code=SDK_GENERATION_ENTRYPOINT_OK") {
                Add-Failure "OPENAPI_SDK_ENTRYPOINT_FAILED" $sdkRunner "SDK generation plan did not emit success evidence"
            }
        }
        catch {
            Add-Failure "OPENAPI_SDK_ENTRYPOINT_FAILED" $sdkRunner $_.Exception.Message
        }
    }

    foreach ($requiredText in @(
        '"openapi": "3.1.0"',
        '"/v1/chat/completions"',
        '"operationId": "createChatCompletion"',
        '"BearerAuth"',
        '"ApiKeyAuth"',
        '"200"',
        '"400"',
        '"401"',
        '"403"',
        '"429"',
        '"502"',
        '"text/event-stream"',
        '"CreateChatCompletionRequest"',
        '"ChatCompletion"'
    )) {
        Assert-FileContains $contract $requiredText "OPENAPI_BASELINE_INCOMPLETE"
    }
    Assert-FileNotContains $contract '"402"' "OPENAPI_402_SEMANTICS_UNDECIDED"
    Assert-FileNotContains $contract '"Error"' "OPENAPI_ERROR_SCHEMA_PREMATURE"
    Assert-FileNotContains $contract '"servers"' "OPENAPI_PRODUCTION_DOMAIN_UNDECIDED"
    Assert-FileContains $contract "TBD-008" "OPENAPI_ERROR_TBD_MISSING"
    Assert-FileContains $contract "REQ-API-003" "OPENAPI_AUTH_TBD_MISSING"

    Assert-FileContains $baseline '"baseline_version": 1' "OPENAPI_COMPATIBILITY_BASELINE_MISSING"
    Assert-FileContains $baseline '"schema_property_signatures"' "OPENAPI_SCHEMA_COMPATIBILITY_BASELINE_MISSING"
    Assert-FileContains $openApiRunner 'OPENAPI_BREAKING_PROPERTY_REMOVAL' "OPENAPI_PROPERTY_REMOVAL_GUARD_MISSING"
    Assert-FileContains $openApiRunner 'OPENAPI_BREAKING_PROPERTY_CHANGE' "OPENAPI_PROPERTY_CHANGE_GUARD_MISSING"
    Assert-FileContains $binding '"runtime_handler_status": "TBD-001"' "OPENAPI_HANDLER_LANGUAGE_TBD_MISSING"
    Assert-FileContains $contractReadme "TBD-007" "OPENAPI_SDK_LANGUAGE_TBD_MISSING"
    Assert-FileContains $contractReadme "TBD-008" "OPENAPI_ERROR_SCHEMA_TBD_MISSING"
    Assert-FileContains $contractReadme "breaking-change and migration plan" "OPENAPI_BREAKING_CHANGE_GUARD_MISSING"
    Assert-FileContains $contractReadme "official" "OPENAPI_SOURCE_TRACEABILITY_MISSING"

    Assert-FileContains $workflow "Verify OpenAPI 3.1 Contract" "CI_OPENAPI_TEST_MISSING"
    Assert-FileContains $workflow "test-m2-001" "CI_OPENAPI_COMMAND_MISSING"
}

function Invoke-AuthenticationBoundaryTest {
    $requestSchemaFile = "packages/auth/contracts/authentication-request.v1.schema.json"
    $decisionSchemaFile = "packages/auth/contracts/authentication-decision.v1.schema.json"
    $boundaryFile = "packages/auth/contracts/authentication-boundary.v1.json"
    $conformanceFile = "packages/auth/authentication-boundary.conformance.ps1"
    $bindingFile = "apps/gateway/contracts/chat-completions.binding.v1.json"
    $openApiFile = "docs/contracts/openapi/openapi.yaml"
    $workflow = ".github/workflows/pr-gates.yml"

    foreach ($file in @($requestSchemaFile, $decisionSchemaFile, $boundaryFile, $conformanceFile, $bindingFile, $openApiFile)) {
        Assert-File $file
    }

    $requestSchemaPath = Join-Path $repoRoot $requestSchemaFile
    $decisionSchemaPath = Join-Path $repoRoot $decisionSchemaFile
    $boundaryPath = Join-Path $repoRoot $boundaryFile
    if ((Test-Path -LiteralPath $requestSchemaPath -PathType Leaf) -and
        (Test-Path -LiteralPath $decisionSchemaPath -PathType Leaf) -and
        (Test-Path -LiteralPath $boundaryPath -PathType Leaf)) {
        try {
            $requestSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath $requestSchemaPath | ConvertFrom-Json
            $decisionSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath $decisionSchemaPath | ConvertFrom-Json
            $boundary = Get-Content -Raw -Encoding UTF8 -LiteralPath $boundaryPath | ConvertFrom-Json

            if ($requestSchema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema" -or
                $requestSchema.properties.schema_version.const -ne 1 -or
                $requestSchema.additionalProperties -ne $false) {
                Add-Failure "AUTH_REQUEST_SCHEMA_INVALID" $requestSchemaFile "request contract must be closed and fixed at schema version 1"
            }
            $credentialKinds = @($requestSchema.properties.credential_candidates.items.properties.kind.enum)
            foreach ($kind in @("bearer", "api_key")) {
                if ($credentialKinds -notcontains $kind) {
                    Add-Failure "AUTH_CREDENTIAL_KIND_MISSING" $requestSchemaFile ("missing normalized credential kind: " + $kind)
                }
            }
            if ($requestSchema.properties.credential_candidates.items.properties.value.writeOnly -ne $true) {
                Add-Failure "AUTH_CREDENTIAL_NOT_WRITE_ONLY" $requestSchemaFile "credential values must be marked writeOnly"
            }
            if ($null -ne $requestSchema.properties.request.properties.PSObject.Properties["tenant_id"]) {
                Add-Failure "AUTH_CLIENT_TENANT_OVERRIDE_ALLOWED" $requestSchemaFile "client request context must not supply tenant_id"
            }

            if ($decisionSchema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema" -or
                $decisionSchema.properties.schema_version.const -ne 1 -or
                $decisionSchema.additionalProperties -ne $false) {
                Add-Failure "AUTH_DECISION_SCHEMA_INVALID" $decisionSchemaFile "decision contract must be closed and fixed at schema version 1"
            }
            $principalRequired = @($decisionSchema.'$defs'.principal.required)
            foreach ($field in @("subject_id", "tenant_id", "credential_kind", "scopes")) {
                if ($principalRequired -notcontains $field) {
                    Add-Failure "AUTH_PRINCIPAL_FIELD_MISSING" $decisionSchemaFile ("verified principal field is absent: " + $field)
                }
            }
            foreach ($reason in @(
                "AUTHENTICATED",
                "CREDENTIAL_MISSING",
                "CREDENTIAL_AMBIGUOUS",
                "CREDENTIAL_MALFORMED",
                "CREDENTIAL_INVALID",
                "CREDENTIAL_EXPIRED",
                "CREDENTIAL_REVOKED",
                "AUTHENTICATOR_UNAVAILABLE",
                "AUTHENTICATOR_RESULT_INVALID"
            )) {
                if (@($decisionSchema.properties.reason_code.enum) -notcontains $reason) {
                    Add-Failure "AUTH_REASON_CODE_MISSING" $decisionSchemaFile ("structured authentication reason is absent: " + $reason)
                }
            }

            if ($boundary.interface_version -ne 1 -or
                $boundary.next_boundary.required_authentication_outcome -ne "authenticated" -or
                $boundary.next_boundary.task -ne "TASK-M2-003" -or
                $boundary.next_boundary.status -ne "implemented-v1" -or
                $boundary.next_boundary.contract -ne "docs/contracts/policy-decisions/policy-boundary.v1.json") {
                Add-Failure "AUTH_BOUNDARY_PIPELINE_INVALID" $boundaryFile "only authenticated principals may enter Policy Boundary v1"
            }
            foreach ($dependency in @("control_plane_postgresql", "provider_runtime", "litellm")) {
                if (@($boundary.forbidden_dependencies) -notcontains $dependency) {
                    Add-Failure "AUTH_FORBIDDEN_DEPENDENCY_GUARD_MISSING" $boundaryFile ("forbidden online dependency is absent: " + $dependency)
                }
            }
            if ($boundary.transport_adapter.status -ne "REQ-API-003-TBD" -or
                $null -ne $boundary.transport_adapter.header_name -or
                $boundary.public_error_schema_status -ne "TBD-008" -or
                $boundary.runtime_language_status -ne "TBD-001" -or
                $boundary.dependency_injection_status -ne "TBD-002" -or
                $boundary.secret_manager_status -ne "TBD-012") {
                Add-Failure "AUTH_TBD_BOUNDARY_VIOLATED" $boundaryFile "Header, error, runtime, DI, and Secret Manager decisions must remain unresolved"
            }
        }
        catch {
            Add-Failure "AUTH_CONTRACT_JSON_INVALID" $boundaryFile $_.Exception.Message
        }
    }

    $conformancePath = Join-Path $repoRoot $conformanceFile
    if (Test-Path -LiteralPath $conformancePath -PathType Leaf) {
        try {
            $output = @(& $conformancePath)
            foreach ($line in $output) {
                Write-Output $line
            }
            if ($output -notcontains "status=pass reason_code=AUTHENTICATION_BOUNDARY_CONFORMANCE_OK") {
                Add-Failure "AUTH_CONFORMANCE_FAILED" $conformanceFile "success evidence was not emitted"
            }
        }
        catch {
            Add-Failure "AUTH_CONFORMANCE_FAILED" $conformanceFile $_.Exception.Message
        }
    }

    Assert-FileContains $bindingFile '"authentication_boundary": "packages/auth/contracts/authentication-boundary.v1.json"' "AUTH_GATEWAY_BINDING_MISSING"
    Assert-FileContains $bindingFile '"required_authentication_outcome": "authenticated"' "AUTH_GATEWAY_OUTCOME_GUARD_MISSING"
    Assert-FileContains $bindingFile '"authorization_boundary_task": "TASK-M2-003"' "AUTHORIZATION_BOUNDARY_TRACE_MISSING"
    Assert-FileContains $bindingFile '"policy_boundary": "docs/contracts/policy-decisions/policy-boundary.v1.json"' "AUTHORIZATION_BOUNDARY_BINDING_MISSING"
    Assert-FileContains $openApiFile '"x-authentication-contract"' "AUTH_OPENAPI_TRACE_MISSING"
    Assert-FileContains $openApiFile '"x-credential-kind": "bearer"' "AUTH_OPENAPI_BEARER_KIND_MISSING"
    Assert-FileContains $openApiFile '"x-credential-kind": "api_key"' "AUTH_OPENAPI_API_KEY_KIND_MISSING"
    Assert-FileContains "docs/contracts/openapi/compatibility-baseline.v1.json" '"required_security_credential_kinds"' "AUTH_OPENAPI_COMPATIBILITY_GUARD_MISSING"
    Assert-FileContains $openApiFile "REQ-API-003" "AUTH_HEADER_TBD_MISSING"
    Assert-FileContains "packages/auth/README.md" "must never synchronously query Control Plane" "AUTH_CP_DP_GUARD_MISSING"
    Assert-FileContains "packages/auth/README.md" "cannot supply or override" "AUTH_TENANT_SOURCE_GUARD_MISSING"
    Assert-FileContains "packages/auth/README.md" "must not be persisted" "AUTH_CREDENTIAL_DISCLOSURE_GUARD_MISSING"
    Assert-FileContains $workflow "Verify Authentication Boundary" "CI_AUTH_BOUNDARY_TEST_MISSING"
    Assert-FileContains $workflow "test-m2-002" "CI_AUTH_BOUNDARY_COMMAND_MISSING"
}

function Invoke-PolicyDecisionTest {
    $requestSchemaFile = "docs/contracts/policy-decisions/policy-evaluation-request.v1.schema.json"
    $decisionSchemaFile = "docs/contracts/policy-decisions/policy-decision.v1.schema.json"
    $boundaryFile = "docs/contracts/policy-decisions/policy-boundary.v1.json"
    $baselineFile = "docs/contracts/policy-decisions/policy-compatibility-baseline.v1.json"
    $conformanceFile = "apps/policy/policy-decision.conformance.ps1"
    $bindingFile = "apps/gateway/contracts/chat-completions.binding.v1.json"
    $authBoundaryFile = "packages/auth/contracts/authentication-boundary.v1.json"
    $workflow = ".github/workflows/pr-gates.yml"

    foreach ($file in @($requestSchemaFile, $decisionSchemaFile, $boundaryFile, $baselineFile, $conformanceFile, $bindingFile, $authBoundaryFile)) {
        Assert-File $file
    }

    $requestSchemaPath = Join-Path $repoRoot $requestSchemaFile
    $decisionSchemaPath = Join-Path $repoRoot $decisionSchemaFile
    $boundaryPath = Join-Path $repoRoot $boundaryFile
    $baselinePath = Join-Path $repoRoot $baselineFile
    if ((Test-Path -LiteralPath $requestSchemaPath -PathType Leaf) -and
        (Test-Path -LiteralPath $decisionSchemaPath -PathType Leaf) -and
        (Test-Path -LiteralPath $boundaryPath -PathType Leaf) -and
        (Test-Path -LiteralPath $baselinePath -PathType Leaf)) {
        try {
            $requestSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath $requestSchemaPath | ConvertFrom-Json
            $decisionSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath $decisionSchemaPath | ConvertFrom-Json
            $boundary = Get-Content -Raw -Encoding UTF8 -LiteralPath $boundaryPath | ConvertFrom-Json
            $baseline = Get-Content -Raw -Encoding UTF8 -LiteralPath $baselinePath | ConvertFrom-Json

            if ($baseline.baseline_version -ne 1 -or
                $baseline.request_schema_id -ne $requestSchema.'$id' -or
                $baseline.decision_schema_id -ne $decisionSchema.'$id') {
                Add-Failure "POLICY_COMPATIBILITY_BASELINE_INVALID" $baselineFile "baseline must identify the published request and decision v1 schemas"
            }

            if ($requestSchema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema" -or
                $requestSchema.properties.schema_version.const -ne 1 -or
                $requestSchema.additionalProperties -ne $false) {
                Add-Failure "POLICY_REQUEST_SCHEMA_INVALID" $requestSchemaFile "policy request must be a closed JSON Schema 2020-12 v1 contract"
            }
            foreach ($field in @("request_id", "trace_id", "tenant_id", "config_version", "principal", "resource", "policy_context")) {
                if (@($requestSchema.required) -notcontains $field) {
                    Add-Failure "POLICY_REQUEST_FIELD_MISSING" $requestSchemaFile ("traceable policy input is absent: " + $field)
                }
            }
            foreach ($field in @("tenant_id", "config_version", "policy_version", "policy_ids", "tenant_status", "allowed_models", "allowed_regions", "budget", "obligations")) {
                if (@($requestSchema.properties.policy_context.required) -notcontains $field) {
                    Add-Failure "POLICY_CONTEXT_FIELD_MISSING" $requestSchemaFile ("published policy context is absent: " + $field)
                }
            }
            if ($requestSchema.properties.policy_context.properties.obligations.items.'$ref' -ne 'urn:enterprise-ai-platform:policy:decision:v1#/$defs/obligation') {
                Add-Failure "POLICY_OBLIGATION_REFERENCE_INVALID" $requestSchemaFile "request obligations must resolve to the decision v1 obligation schema"
            }

            if ($decisionSchema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema" -or
                $decisionSchema.properties.schema_version.const -ne 1 -or
                $decisionSchema.additionalProperties -ne $false) {
                Add-Failure "POLICY_DECISION_SCHEMA_INVALID" $decisionSchemaFile "policy decision must be a closed JSON Schema 2020-12 v1 contract"
            }
            foreach ($field in @("allow", "deny_reason", "obligations", "matched_policy_ids", "policy_version")) {
                if (@($decisionSchema.required) -notcontains $field) {
                    Add-Failure "POLICY_DECISION_FIELD_MISSING" $decisionSchemaFile ("REQ-CODE-003 decision field is absent: " + $field)
                }
            }
            foreach ($field in @("request_id", "trace_id", "tenant_id", "config_version", "model_alias", "outcome", "reason_code")) {
                if (@($decisionSchema.required) -notcontains $field) {
                    Add-Failure "POLICY_TRACE_FIELD_MISSING" $decisionSchemaFile ("REQ-GEN-005 decision context is absent: " + $field)
                }
            }
            $obligationKinds = @($decisionSchema.'$defs'.obligation.oneOf | ForEach-Object { $_.properties.kind.const })
            foreach ($kind in @("mask", "redact", "force_region", "disable_body_logging", "limit_max_tokens")) {
                if ($obligationKinds -notcontains $kind) {
                    Add-Failure "POLICY_OBLIGATION_KIND_MISSING" $decisionSchemaFile ("required obligation kind is absent: " + $kind)
                }
                if (@($baseline.required_obligation_kinds) -notcontains $kind) {
                    Add-Failure "POLICY_COMPATIBILITY_OBLIGATION_MISSING" $baselineFile ("baseline obligation kind is absent: " + $kind)
                }
            }
            foreach ($outcome in @("allow", "deny", "indeterminate")) {
                if (@($decisionSchema.properties.outcome.enum) -notcontains $outcome -or @($baseline.required_outcomes) -notcontains $outcome) {
                    Add-Failure "POLICY_COMPATIBILITY_OUTCOME_MISSING" $baselineFile ("published outcome is absent: " + $outcome)
                }
            }
            foreach ($field in @($baseline.required_request_fields)) {
                if (@($requestSchema.required) -notcontains $field) {
                    Add-Failure "POLICY_BREAKING_REQUEST_FIELD_REMOVAL" $requestSchemaFile ("baseline request field was removed: " + $field)
                }
            }
            foreach ($field in @($baseline.required_policy_context_fields)) {
                if (@($requestSchema.properties.policy_context.required) -notcontains $field) {
                    Add-Failure "POLICY_BREAKING_CONTEXT_FIELD_REMOVAL" $requestSchemaFile ("baseline policy-context field was removed: " + $field)
                }
            }
            foreach ($field in @($baseline.required_decision_fields)) {
                if (@($decisionSchema.required) -notcontains $field) {
                    Add-Failure "POLICY_BREAKING_DECISION_FIELD_REMOVAL" $decisionSchemaFile ("baseline decision field was removed: " + $field)
                }
            }

            if ($boundary.interface_version -ne 1 -or
                $null -ne $boundary.runtime -or
                $boundary.runtime_status -ne "TBD-004" -or
                $null -ne $boundary.indeterminate_handling.mapping -or
                $boundary.indeterminate_handling.status -ne "TBD-017" -or
                $boundary.next_boundary.task -ne "TASK-M2-004" -or
                $boundary.next_boundary.status -ne "implemented-v1" -or
                $boundary.next_boundary.contract -ne "docs/contracts/router/router-boundary.v1.json" -or
                $boundary.next_boundary.required_policy_outcome -ne "allow" -or
                $baseline.required_router_outcome -ne "allow") {
                Add-Failure "POLICY_TBD_OR_PIPELINE_BOUNDARY_INVALID" $boundaryFile "runtime/failure defaults must remain TBD and only allow may reach routing"
            }
            foreach ($dependency in @("control_plane_postgresql", "provider_runtime", "litellm")) {
                if (@($boundary.forbidden_dependencies) -notcontains $dependency) {
                    Add-Failure "POLICY_FORBIDDEN_DEPENDENCY_GUARD_MISSING" $boundaryFile ("forbidden online dependency is absent: " + $dependency)
                }
            }
        }
        catch {
            Add-Failure "POLICY_CONTRACT_JSON_INVALID" $boundaryFile $_.Exception.Message
        }
    }

    $conformancePath = Join-Path $repoRoot $conformanceFile
    if (Test-Path -LiteralPath $conformancePath -PathType Leaf) {
        try {
            $output = @(& $conformancePath)
            foreach ($line in $output) {
                Write-Output $line
            }
            if ($output -notcontains "status=pass reason_code=POLICY_DECISION_CONFORMANCE_OK") {
                Add-Failure "POLICY_CONFORMANCE_FAILED" $conformanceFile "success evidence was not emitted"
            }
        }
        catch {
            Add-Failure "POLICY_CONFORMANCE_FAILED" $conformanceFile $_.Exception.Message
        }
    }

    Assert-FileNotContains $decisionSchemaFile '"policy_source"' "POLICY_SOURCE_DISCLOSURE_FORBIDDEN"
    Assert-FileNotContains $decisionSchemaFile '"provider_key"' "POLICY_PROVIDER_KEY_DISCLOSURE_FORBIDDEN"
    Assert-FileContains $bindingFile '"policy_boundary": "docs/contracts/policy-decisions/policy-boundary.v1.json"' "POLICY_GATEWAY_BINDING_MISSING"
    Assert-FileContains $bindingFile '"required_policy_outcome": "allow"' "POLICY_GATEWAY_ALLOW_GUARD_MISSING"
    Assert-FileContains $bindingFile '"policy_runtime_status": "TBD-004"' "POLICY_RUNTIME_TBD_MISSING"
    Assert-FileContains $authBoundaryFile '"status": "implemented-v1"' "AUTH_TO_POLICY_BINDING_INCOMPLETE"
    Assert-FileContains "docs/contracts/policy-decisions/README.md" "must not synchronously query Control Plane" "POLICY_CP_DP_GUARD_MISSING"
    Assert-FileContains "docs/contracts/policy-decisions/README.md" "TBD-017" "POLICY_FAILURE_POLICY_TBD_MISSING"
    Assert-FileContains $workflow "Verify Policy Decision Boundary" "CI_POLICY_BOUNDARY_TEST_MISSING"
    Assert-FileContains $workflow "test-m2-003" "CI_POLICY_BOUNDARY_COMMAND_MISSING"
}

function Invoke-RouterPluginTest {
    $requestSchemaFile = "docs/contracts/router/router-request.v1.schema.json"
    $pluginResultSchemaFile = "docs/contracts/router/router-plugin-result.v1.schema.json"
    $decisionSchemaFile = "docs/contracts/router/route-decision.v1.schema.json"
    $registrySchemaFile = "docs/contracts/router/router-registry.v1.schema.json"
    $boundaryFile = "docs/contracts/router/router-boundary.v1.json"
    $baselineFile = "docs/contracts/router/router-compatibility-baseline.v1.json"
    $conformanceFile = "apps/router/router-plugin.conformance.ps1"
    $policyBoundaryFile = "docs/contracts/policy-decisions/policy-boundary.v1.json"
    $bindingFile = "apps/gateway/contracts/chat-completions.binding.v1.json"
    $workflow = ".github/workflows/pr-gates.yml"

    foreach ($file in @($requestSchemaFile, $pluginResultSchemaFile, $decisionSchemaFile, $registrySchemaFile, $boundaryFile, $baselineFile, $conformanceFile, $policyBoundaryFile, $bindingFile)) {
        Assert-File $file
    }

    try {
        $requestSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $requestSchemaFile) | ConvertFrom-Json
        $pluginResultSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $pluginResultSchemaFile) | ConvertFrom-Json
        $decisionSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $decisionSchemaFile) | ConvertFrom-Json
        $registrySchema = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $registrySchemaFile) | ConvertFrom-Json
        $boundary = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $boundaryFile) | ConvertFrom-Json
        $baseline = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $baselineFile) | ConvertFrom-Json

        foreach ($schema in @($requestSchema, $pluginResultSchema, $decisionSchema, $registrySchema)) {
            if ($schema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema" -or $schema.additionalProperties -ne $false) {
                Add-Failure "ROUTER_SCHEMA_INVALID" $boundaryFile "all Router v1 envelopes must be closed JSON Schema 2020-12 contracts"
            }
        }
        if ($baseline.baseline_version -ne 1 -or
            $baseline.request_schema_id -ne $requestSchema.'$id' -or
            $baseline.plugin_result_schema_id -ne $pluginResultSchema.'$id' -or
            $baseline.decision_schema_id -ne $decisionSchema.'$id' -or
            $baseline.registry_schema_id -ne $registrySchema.'$id') {
            Add-Failure "ROUTER_COMPATIBILITY_BASELINE_INVALID" $baselineFile "baseline must identify every published Router v1 schema"
        }

        foreach ($pair in @(
            [PSCustomObject]@{ Schema = $requestSchema; Fields = @($baseline.required_request_fields); Subject = $requestSchemaFile; Reason = "ROUTER_BREAKING_REQUEST_FIELD_REMOVAL" },
            [PSCustomObject]@{ Schema = $pluginResultSchema; Fields = @($baseline.required_plugin_result_fields); Subject = $pluginResultSchemaFile; Reason = "ROUTER_BREAKING_PLUGIN_FIELD_REMOVAL" },
            [PSCustomObject]@{ Schema = $decisionSchema; Fields = @($baseline.required_decision_fields); Subject = $decisionSchemaFile; Reason = "ROUTER_BREAKING_DECISION_FIELD_REMOVAL" },
            [PSCustomObject]@{ Schema = $registrySchema; Fields = @($baseline.required_registry_fields); Subject = $registrySchemaFile; Reason = "ROUTER_BREAKING_REGISTRY_FIELD_REMOVAL" }
        )) {
            foreach ($field in $pair.Fields) {
                if (@($pair.Schema.required) -notcontains $field) {
                    Add-Failure $pair.Reason $pair.Subject ("baseline field was removed: " + $field)
                }
            }
        }
        foreach ($outcome in @("applied", "skipped", "rejected", "indeterminate")) {
            if (@($pluginResultSchema.properties.outcome.enum) -notcontains $outcome -or @($baseline.required_plugin_outcomes) -notcontains $outcome) {
                Add-Failure "ROUTER_PLUGIN_OUTCOME_MISSING" $pluginResultSchemaFile ("published plugin outcome is absent: " + $outcome)
            }
        }
        foreach ($outcome in @("selected", "no_route", "indeterminate")) {
            if (@($decisionSchema.properties.outcome.enum) -notcontains $outcome -or @($baseline.required_route_outcomes) -notcontains $outcome) {
                Add-Failure "ROUTER_DECISION_OUTCOME_MISSING" $decisionSchemaFile ("published route outcome is absent: " + $outcome)
            }
        }

        $candidateProperties = @($requestSchema.properties.candidates.items.properties.PSObject.Properties.Name)
        foreach ($field in @("provider_id", "region", "priority", "weight", "enabled")) {
            if ($candidateProperties -notcontains $field) {
                Add-Failure "ROUTER_CANDIDATE_FIELD_MISSING" $requestSchemaFile ("candidate routing metadata is absent: " + $field)
            }
        }
        foreach ($forbidden in @("endpoint", "secret_ref", "provider_key", "credential")) {
            if ($candidateProperties -contains $forbidden -or $null -ne $decisionSchema.properties.PSObject.Properties[$forbidden]) {
                Add-Failure "ROUTER_SECRET_OR_ENDPOINT_FIELD_FORBIDDEN" $requestSchemaFile ("forbidden Router field is present: " + $forbidden)
            }
            if (@($boundary.forbidden_fields) -notcontains $forbidden) {
                Add-Failure "ROUTER_FORBIDDEN_FIELD_GUARD_MISSING" $boundaryFile ("forbidden field guard is absent: " + $forbidden)
            }
        }

        if ($requestSchema.properties.policy.properties.outcome.const -ne "allow" -or
            $null -ne $boundary.plugin_method_signature -or
            $boundary.plugin_method_signature_status -ne "TBD-003" -or
            $null -ne $boundary.selection_algorithm -or
            $null -ne $boundary.weight_and_observation_semantics -or
            $boundary.weight_and_observation_status -ne "TBD-014" -or
            $null -ne $boundary.indeterminate_handling.mapping -or
            $boundary.indeterminate_handling.status -ne "TBD-017" -or
            $boundary.next_boundary.task -ne "TASK-M2-005" -or
            $boundary.next_boundary.status -ne "implemented-v1" -or
            $boundary.next_boundary.contract -ne "docs/contracts/providers/provider-adapter-boundary.v1.json" -or
            $boundary.next_boundary.required_route_outcome -ne "selected" -or
            $baseline.required_provider_adapter_outcome -ne "selected") {
            Add-Failure "ROUTER_TBD_OR_PIPELINE_BOUNDARY_INVALID" $boundaryFile "method/algorithm/weight/failure defaults must remain unresolved and only selected may reach the Provider Adapter"
        }
        foreach ($dependency in @("control_plane_postgresql", "litellm_governance_state")) {
            if (@($boundary.forbidden_dependencies) -notcontains $dependency) {
                Add-Failure "ROUTER_FORBIDDEN_DEPENDENCY_GUARD_MISSING" $boundaryFile ("forbidden online dependency is absent: " + $dependency)
            }
        }
    }
    catch {
        Add-Failure "ROUTER_CONTRACT_JSON_INVALID" $boundaryFile $_.Exception.Message
    }

    $conformancePath = Join-Path $repoRoot $conformanceFile
    if (Test-Path -LiteralPath $conformancePath -PathType Leaf) {
        try {
            $output = @(& $conformancePath)
            foreach ($line in $output) { Write-Output $line }
            if ($output -notcontains "status=pass reason_code=ROUTER_PLUGIN_CONFORMANCE_OK") {
                Add-Failure "ROUTER_CONFORMANCE_FAILED" $conformanceFile "success evidence was not emitted"
            }
        }
        catch {
            Add-Failure "ROUTER_CONFORMANCE_FAILED" $conformanceFile $_.Exception.Message
        }
    }

    Assert-FileNotContains $conformanceFile 'switch ([string]$Request.route_strategy)' "ROUTER_STRATEGY_DISPATCH_CHAIN_FORBIDDEN"
    Assert-FileContains $policyBoundaryFile '"status": "implemented-v1"' "POLICY_TO_ROUTER_BINDING_INCOMPLETE"
    Assert-FileContains $policyBoundaryFile '"contract": "docs/contracts/router/router-boundary.v1.json"' "POLICY_TO_ROUTER_CONTRACT_MISSING"
    Assert-FileContains $bindingFile '"router_boundary": "docs/contracts/router/router-boundary.v1.json"' "ROUTER_GATEWAY_BINDING_MISSING"
    Assert-FileContains $bindingFile '"required_route_outcome": "selected"' "ROUTER_GATEWAY_SELECTED_GUARD_MISSING"
    Assert-FileContains $bindingFile '"router_plugin_method_status": "TBD-003"' "ROUTER_METHOD_TBD_MISSING"
    Assert-FileContains "docs/contracts/router/README.md" "must not query Control Plane PostgreSQL" "ROUTER_CP_DP_GUARD_MISSING"
    Assert-FileContains "docs/contracts/router/README.md" "TBD-014" "ROUTER_WEIGHT_TBD_MISSING"
    Assert-FileContains $workflow "Verify Router Plugin Boundary" "CI_ROUTER_BOUNDARY_TEST_MISSING"
    Assert-FileContains $workflow "test-m2-004" "CI_ROUTER_BOUNDARY_COMMAND_MISSING"
}

function Invoke-ProviderAdapterTest {
    $requestSchemaFile = "docs/contracts/providers/provider-invocation-request.v1.schema.json"
    $resultSchemaFile = "docs/contracts/providers/provider-invocation-result.v1.schema.json"
    $runtimeConfigSchemaFile = "docs/contracts/providers/provider-runtime-config.v1.schema.json"
    $registrySchemaFile = "docs/contracts/providers/provider-adapter-registry.v1.schema.json"
    $boundaryFile = "docs/contracts/providers/provider-adapter-boundary.v1.json"
    $litellmBoundaryFile = "docs/contracts/providers/litellm-runtime-boundary.v1.json"
    $baselineFile = "docs/contracts/providers/provider-compatibility-baseline.v1.json"
    $conformanceFile = "apps/provider/provider-adapter.conformance.ps1"
    $routerBoundaryFile = "docs/contracts/router/router-boundary.v1.json"
    $bindingFile = "apps/gateway/contracts/chat-completions.binding.v1.json"
    $workflow = ".github/workflows/pr-gates.yml"

    foreach ($file in @($requestSchemaFile, $resultSchemaFile, $runtimeConfigSchemaFile, $registrySchemaFile, $boundaryFile, $litellmBoundaryFile, $baselineFile, $conformanceFile, $routerBoundaryFile, $bindingFile)) {
        Assert-File $file
    }

    try {
        $requestSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $requestSchemaFile) | ConvertFrom-Json
        $resultSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $resultSchemaFile) | ConvertFrom-Json
        $runtimeConfigSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $runtimeConfigSchemaFile) | ConvertFrom-Json
        $registrySchema = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $registrySchemaFile) | ConvertFrom-Json
        $boundary = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $boundaryFile) | ConvertFrom-Json
        $litellmBoundary = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $litellmBoundaryFile) | ConvertFrom-Json
        $baseline = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $baselineFile) | ConvertFrom-Json

        foreach ($schema in @($requestSchema, $resultSchema, $runtimeConfigSchema, $registrySchema)) {
            if ($schema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema" -or $schema.additionalProperties -ne $false) {
                Add-Failure "PROVIDER_SCHEMA_INVALID" $boundaryFile "all Provider v1 envelopes must be closed JSON Schema 2020-12 contracts"
            }
        }
        if ($baseline.baseline_version -ne 1 -or
            $baseline.request_schema_id -ne $requestSchema.'$id' -or
            $baseline.result_schema_id -ne $resultSchema.'$id' -or
            $baseline.runtime_config_schema_id -ne $runtimeConfigSchema.'$id' -or
            $baseline.registry_schema_id -ne $registrySchema.'$id') {
            Add-Failure "PROVIDER_COMPATIBILITY_BASELINE_INVALID" $baselineFile "baseline must identify every published Provider v1 schema"
        }

        foreach ($pair in @(
            [PSCustomObject]@{ Schema = $requestSchema; Fields = @($baseline.required_request_fields); Subject = $requestSchemaFile; Reason = "PROVIDER_BREAKING_REQUEST_FIELD_REMOVAL" },
            [PSCustomObject]@{ Schema = $resultSchema; Fields = @($baseline.required_result_fields); Subject = $resultSchemaFile; Reason = "PROVIDER_BREAKING_RESULT_FIELD_REMOVAL" },
            [PSCustomObject]@{ Schema = $runtimeConfigSchema; Fields = @($baseline.required_runtime_config_fields); Subject = $runtimeConfigSchemaFile; Reason = "PROVIDER_BREAKING_CONFIG_FIELD_REMOVAL" },
            [PSCustomObject]@{ Schema = $registrySchema; Fields = @($baseline.required_registry_fields); Subject = $registrySchemaFile; Reason = "PROVIDER_BREAKING_REGISTRY_FIELD_REMOVAL" }
        )) {
            foreach ($field in $pair.Fields) {
                if (@($pair.Schema.required) -notcontains $field) {
                    Add-Failure $pair.Reason $pair.Subject ("baseline field was removed: " + $field)
                }
            }
        }
        foreach ($outcome in @("succeeded", "failed", "indeterminate")) {
            if (@($resultSchema.properties.outcome.enum) -notcontains $outcome -or @($baseline.required_outcomes) -notcontains $outcome) {
                Add-Failure "PROVIDER_OUTCOME_MISSING" $resultSchemaFile ("published result outcome is absent: " + $outcome)
            }
        }
        if ($resultSchema.allOf[0].else.properties.error_kind.type -ne "string" -or
            @($resultSchema.allOf[0].else.properties.retry_hint.enum) -contains "not_applicable" -or
            $registrySchema.properties.adapters.minItems -ne 1) {
            Add-Failure "PROVIDER_FAILURE_OR_REGISTRY_SCHEMA_INVALID" $resultSchemaFile "non-success results require structured error classification and the registry must be non-empty"
        }
        foreach ($runtimeKind in @("native", "litellm")) {
            if (@($registrySchema.properties.adapters.items.properties.runtime_kind.enum) -notcontains $runtimeKind -or @($baseline.required_runtime_kinds) -notcontains $runtimeKind) {
                Add-Failure "PROVIDER_RUNTIME_KIND_MISSING" $registrySchemaFile ("published runtime kind is absent: " + $runtimeKind)
            }
        }

        if ($requestSchema.properties.route.properties.outcome.const -ne "selected") {
            Add-Failure "PROVIDER_SELECTED_ROUTE_GUARD_MISSING" $requestSchemaFile "only a selected Route Decision may enter the Provider Adapter"
        }
        $requestProperties = @($requestSchema.properties.PSObject.Properties.Name)
        $resultProperties = @($resultSchema.properties.PSObject.Properties.Name)
        foreach ($forbidden in @("endpoint", "secret_ref", "provider_model", "provider_key", "credential")) {
            if ($requestProperties -contains $forbidden -or @($boundary.forbidden_upper_layer_fields) -notcontains $forbidden) {
                Add-Failure "PROVIDER_UPPER_LAYER_FIELD_FORBIDDEN" $requestSchemaFile ("upper-layer field guard is invalid: " + $forbidden)
            }
        }
        foreach ($forbidden in @("endpoint", "secret_ref", "provider_model", "provider_key", "credential", "raw_error", "stack_trace")) {
            if ($resultProperties -contains $forbidden -or @($boundary.forbidden_result_fields) -notcontains $forbidden) {
                Add-Failure "PROVIDER_RESULT_FIELD_FORBIDDEN" $resultSchemaFile ("result field guard is invalid: " + $forbidden)
            }
        }
        foreach ($internalField in @("provider_model", "endpoint", "secret_ref")) {
            if ($null -eq $runtimeConfigSchema.properties.PSObject.Properties[$internalField] -or $runtimeConfigSchema.properties.$internalField.writeOnly -ne $true) {
                Add-Failure "PROVIDER_INTERNAL_CONFIG_GUARD_MISSING" $runtimeConfigSchemaFile ("internal field must be writeOnly: " + $internalField)
            }
        }
        if ($null -ne $runtimeConfigSchema.properties.PSObject.Properties["provider_key"] -or
            $boundary.status -ne "implemented-v1" -or
            $null -ne $boundary.adapter_method_signature -or
            $boundary.adapter_method_signature_status -ne "TBD-001" -or
            $null -ne $boundary.secret_resolver -or
            $boundary.secret_resolver_status -ne "TBD-012" -or
            $boundary.retry_and_fallback.implementation -ne "docs/contracts/retry-fallback/retry-fallback-boundary.v1.json" -or
            $boundary.retry_and_fallback.status -ne "implemented-v1") {
            Add-Failure "PROVIDER_TBD_OR_SECRET_BOUNDARY_INVALID" $boundaryFile "runtime/DI and Secret Manager remain explicit, Retry/Fallback is delegated, and plaintext keys are forbidden"
        }
        foreach ($dependency in @("control_plane_postgresql", "litellm_governance_state")) {
            if (@($boundary.forbidden_dependencies) -notcontains $dependency) {
                Add-Failure "PROVIDER_FORBIDDEN_DEPENDENCY_GUARD_MISSING" $boundaryFile ("forbidden online dependency is absent: " + $dependency)
            }
        }

        if ($null -ne $litellmBoundary.deployment_mode -or
            $null -ne $litellmBoundary.version -or
            $litellmBoundary.retry_fallback_mode -ne "platform_orchestrator" -or
            $litellmBoundary.retry_fallback_status -ne "implemented-v1" -or
            $litellmBoundary.role -ne "provider_protocol_normalization" -or
            $litellmBoundary.logging_body_default -ne "disabled") {
            Add-Failure "LITELLM_RUNTIME_BOUNDARY_INVALID" $litellmBoundaryFile "LiteLLM may normalize Provider protocol only; platform orchestration owns Retry/Fallback and deployment/version remain unresolved"
        }
        foreach ($governanceOwner in @("tenant", "authentication", "authorization", "policy", "budget", "router", "audit", "config_version")) {
            if (@($litellmBoundary.platform_owned_governance) -notcontains $governanceOwner) {
                Add-Failure "LITELLM_GOVERNANCE_OWNERSHIP_MISSING" $litellmBoundaryFile ("platform governance owner is absent: " + $governanceOwner)
            }
            if (@($litellmBoundary.runtime_allowed_responsibilities) -contains $governanceOwner) {
                Add-Failure "LITELLM_GOVERNANCE_RESPONSIBILITY_FORBIDDEN" $litellmBoundaryFile ("LiteLLM must not own platform governance: " + $governanceOwner)
            }
        }
    }
    catch {
        Add-Failure "PROVIDER_CONTRACT_JSON_INVALID" $boundaryFile $_.Exception.Message
    }

    $conformancePath = Join-Path $repoRoot $conformanceFile
    if (Test-Path -LiteralPath $conformancePath -PathType Leaf) {
        try {
            $output = @(& $conformancePath)
            foreach ($line in $output) { Write-Output $line }
            if ($output -notcontains "status=pass reason_code=PROVIDER_ADAPTER_CONFORMANCE_OK") {
                Add-Failure "PROVIDER_CONFORMANCE_FAILED" $conformanceFile "success evidence was not emitted"
            }
        }
        catch {
            Add-Failure "PROVIDER_CONFORMANCE_FAILED" $conformanceFile $_.Exception.Message
        }
    }

    Assert-FileContains $routerBoundaryFile '"status": "implemented-v1"' "ROUTER_TO_PROVIDER_BINDING_INCOMPLETE"
    Assert-FileContains $routerBoundaryFile '"contract": "docs/contracts/providers/provider-adapter-boundary.v1.json"' "ROUTER_TO_PROVIDER_CONTRACT_MISSING"
    Assert-FileContains $bindingFile '"provider_adapter_boundary": "docs/contracts/providers/provider-adapter-boundary.v1.json"' "PROVIDER_GATEWAY_BINDING_MISSING"
    Assert-FileContains $bindingFile '"retry_fallback_boundary_status": "implemented-v1"' "PROVIDER_RETRY_BOUNDARY_MISSING"
    Assert-FileContains "docs/contracts/providers/README.md" "must not synchronously query Control Plane PostgreSQL" "PROVIDER_CP_DP_GUARD_MISSING"
    Assert-FileContains "docs/contracts/providers/README.md" "TBD-012" "PROVIDER_SECRET_MANAGER_TBD_MISSING"
    Assert-FileContains $workflow "Verify Provider Adapter Boundary" "CI_PROVIDER_BOUNDARY_TEST_MISSING"
    Assert-FileContains $workflow "test-m2-005" "CI_PROVIDER_BOUNDARY_COMMAND_MISSING"
}

function Invoke-RetryFallbackTest {
    $requestSchemaFile = "docs/contracts/retry-fallback/retry-fallback-request.v1.schema.json"
    $planSchemaFile = "docs/contracts/retry-fallback/retry-fallback-plan.v1.schema.json"
    $resultSchemaFile = "docs/contracts/retry-fallback/retry-fallback-result.v1.schema.json"
    $telemetrySchemaFile = "docs/contracts/retry-fallback/retry-fallback-telemetry.v1.schema.json"
    $boundaryFile = "docs/contracts/retry-fallback/retry-fallback-boundary.v1.json"
    $baselineFile = "docs/contracts/retry-fallback/retry-fallback-compatibility-baseline.v1.json"
    $conformanceFile = "apps/provider/retry-fallback.conformance.ps1"
    $providerBoundaryFile = "docs/contracts/providers/provider-adapter-boundary.v1.json"
    $litellmBoundaryFile = "docs/contracts/providers/litellm-runtime-boundary.v1.json"
    $bindingFile = "apps/gateway/contracts/chat-completions.binding.v1.json"
    $snapshotSchemaFile = "docs/contracts/runtime-snapshots/runtime-snapshot.v1.schema.json"
    $workflow = ".github/workflows/pr-gates.yml"

    foreach ($file in @($requestSchemaFile, $planSchemaFile, $resultSchemaFile, $telemetrySchemaFile, $boundaryFile, $baselineFile, $conformanceFile, $providerBoundaryFile, $litellmBoundaryFile, $bindingFile, $snapshotSchemaFile)) {
        Assert-File $file
    }

    try {
        $requestSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $requestSchemaFile) | ConvertFrom-Json
        $planSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $planSchemaFile) | ConvertFrom-Json
        $resultSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $resultSchemaFile) | ConvertFrom-Json
        $telemetrySchema = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $telemetrySchemaFile) | ConvertFrom-Json
        $boundary = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $boundaryFile) | ConvertFrom-Json
        $baseline = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $baselineFile) | ConvertFrom-Json

        foreach ($schema in @($requestSchema, $planSchema, $resultSchema, $telemetrySchema)) {
            if ($schema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema" -or $schema.additionalProperties -ne $false) {
                Add-Failure "RETRY_FALLBACK_SCHEMA_INVALID" $boundaryFile "all Retry/Fallback v1 envelopes must be closed JSON Schema 2020-12 contracts"
            }
        }
        if ($baseline.baseline_version -ne 1 -or
            $baseline.request_schema_id -ne $requestSchema.'$id' -or
            $baseline.plan_schema_id -ne $planSchema.'$id' -or
            $baseline.result_schema_id -ne $resultSchema.'$id' -or
            $baseline.telemetry_schema_id -ne $telemetrySchema.'$id') {
            Add-Failure "RETRY_FALLBACK_COMPATIBILITY_BASELINE_INVALID" $baselineFile "baseline must identify every published Retry/Fallback v1 schema"
        }

        foreach ($pair in @(
            [PSCustomObject]@{ Schema = $requestSchema; Fields = @($baseline.required_request_fields); Subject = $requestSchemaFile; Reason = "RETRY_FALLBACK_BREAKING_REQUEST_FIELD_REMOVAL" },
            [PSCustomObject]@{ Schema = $planSchema; Fields = @($baseline.required_plan_fields); Subject = $planSchemaFile; Reason = "RETRY_FALLBACK_BREAKING_PLAN_FIELD_REMOVAL" },
            [PSCustomObject]@{ Schema = $resultSchema; Fields = @($baseline.required_result_fields); Subject = $resultSchemaFile; Reason = "RETRY_FALLBACK_BREAKING_RESULT_FIELD_REMOVAL" },
            [PSCustomObject]@{ Schema = $telemetrySchema; Fields = @($baseline.required_telemetry_fields); Subject = $telemetrySchemaFile; Reason = "RETRY_FALLBACK_BREAKING_TELEMETRY_FIELD_REMOVAL" }
        )) {
            foreach ($field in $pair.Fields) {
                if (@($pair.Schema.required) -notcontains $field) {
                    Add-Failure $pair.Reason $pair.Subject ("baseline field was removed: " + $field)
                }
            }
        }
        foreach ($action in @("initial", "retry", "fallback")) {
            if (@($planSchema.properties.steps.items.properties.action.enum) -notcontains $action -or
                @($telemetrySchema.'$defs'.attempt.properties.action.enum) -notcontains $action -or
                @($baseline.required_actions) -notcontains $action) {
                Add-Failure "RETRY_FALLBACK_ACTION_MISSING" $planSchemaFile ("published attempt action is absent: " + $action)
            }
        }
        foreach ($outcome in @("succeeded", "failed", "indeterminate")) {
            if (@($resultSchema.properties.outcome.enum) -notcontains $outcome -or
                @($telemetrySchema.properties.outcome.enum) -notcontains $outcome -or
                @($baseline.required_outcomes) -notcontains $outcome) {
                Add-Failure "RETRY_FALLBACK_OUTCOME_MISSING" $resultSchemaFile ("published orchestration outcome is absent: " + $outcome)
            }
        }
        foreach ($errorKind in @("authentication", "rate_limit", "timeout", "provider_error", "invalid_response", "unavailable")) {
            if (@($planSchema.'$defs'.error_kind.enum) -notcontains $errorKind -or
                @($telemetrySchema.'$defs'.error_kind.enum) -notcontains $errorKind -or
                @($baseline.required_error_kinds) -notcontains $errorKind) {
                Add-Failure "RETRY_FALLBACK_ERROR_KIND_MISSING" $planSchemaFile ("published Provider error kind is absent: " + $errorKind)
            }
        }

        if ($requestSchema.properties.invocation.'$ref' -ne "urn:enterprise-ai-platform:provider:invocation-request:v1" -or
            $resultSchema.properties.final_provider_result.oneOf[0].'$ref' -ne "urn:enterprise-ai-platform:provider:invocation-result:v1" -or
            $resultSchema.properties.telemetry.'$ref' -ne "urn:enterprise-ai-platform:retry-fallback:telemetry:v1" -or
            $planSchema.properties.steps.minItems -ne 1 -or
            $null -ne $planSchema.properties.attempt_limit.PSObject.Properties["default"]) {
            Add-Failure "RETRY_FALLBACK_PROVIDER_OR_PLAN_BINDING_INVALID" $boundaryFile "orchestration must bind Provider v1 contracts and require an explicit non-empty plan without defaults"
        }
        if ($boundary.status -ne "implemented-v1" -or
            $null -ne $boundary.orchestrator_method_signature -or
            $boundary.orchestrator_method_signature_status -ne "TBD-001" -or
            $boundary.dependency_injection_status -ne "TBD-002" -or
            $null -ne $boundary.global_attempt_limit_default -or
            $boundary.attempt_limit_source -ne "plan.attempt_limit" -or
            $null -ne $boundary.timing_policy.backoff_algorithm -or
            $null -ne $boundary.timing_policy.jitter_algorithm -or
            $boundary.timing_policy.status -ne "ADR_NEEDED" -or
            $null -ne $boundary.public_failure_mapping.mapping -or
            $boundary.public_failure_mapping.status -ne "TBD-008/TBD-017" -or
            $null -ne $boundary.streaming_retry_policy.retry_after_partial_output -or
            $boundary.streaming_retry_policy.status -ne "ADR_NEEDED") {
            Add-Failure "RETRY_FALLBACK_TBD_OR_DEFAULT_BOUNDARY_INVALID" $boundaryFile "runtime signature, timing algorithms, public mapping, and global attempt defaults must remain explicit TBD/ADR items"
        }
        if ($boundary.next_boundary.task -ne "TASK-M2-007" -or
            $boundary.next_boundary.status -ne "implemented-v1" -or
            $boundary.next_boundary.contract -ne "docs/contracts/events/usage/usage-event-boundary.v1.json" -or
            $boundary.next_boundary.async_required -ne $true) {
            Add-Failure "RETRY_FALLBACK_ASYNC_USAGE_BOUNDARY_INVALID" $boundaryFile "Usage must use the implemented asynchronous TASK-M2-007 boundary"
        }
        foreach ($metric in @("provider_attempt_total", "provider_attempt_duration_ms", "retry_fallback_completed_total")) {
            if (@($boundary.telemetry_projection.metrics) -notcontains $metric) {
                Add-Failure "RETRY_FALLBACK_METRIC_MISSING" $boundaryFile ("required telemetry projection is absent: " + $metric)
            }
        }
        foreach ($label in @("request_id", "trace_id", "user_id")) {
            if (@($boundary.telemetry_projection.forbidden_metric_labels) -notcontains $label) {
                Add-Failure "RETRY_FALLBACK_HIGH_CARDINALITY_GUARD_MISSING" $boundaryFile ("forbidden metric label guard is absent: " + $label)
            }
        }
        foreach ($dependency in @("control_plane_postgresql", "litellm_governance_state", "synchronous_usage_sql", "synchronous_billing_sql", "synchronous_audit_sql")) {
            if (@($boundary.forbidden_dependencies) -notcontains $dependency) {
                Add-Failure "RETRY_FALLBACK_FORBIDDEN_DEPENDENCY_GUARD_MISSING" $boundaryFile ("forbidden online dependency is absent: " + $dependency)
            }
        }
        foreach ($field in @("endpoint", "secret_ref", "provider_model", "provider_key", "credential", "prompt", "response_body", "raw_error", "stack_trace")) {
            if (@($boundary.forbidden_fields) -notcontains $field) {
                Add-Failure "RETRY_FALLBACK_FORBIDDEN_FIELD_GUARD_MISSING" $boundaryFile ("secret/body/internal field guard is absent: " + $field)
            }
        }
    }
    catch {
        Add-Failure "RETRY_FALLBACK_CONTRACT_JSON_INVALID" $boundaryFile $_.Exception.Message
    }

    $conformancePath = Join-Path $repoRoot $conformanceFile
    if (Test-Path -LiteralPath $conformancePath -PathType Leaf) {
        try {
            $output = @(& $conformancePath)
            foreach ($line in $output) { Write-Output $line }
            if ($output -notcontains "status=pass reason_code=RETRY_FALLBACK_CONFORMANCE_OK") {
                Add-Failure "RETRY_FALLBACK_CONFORMANCE_FAILED" $conformanceFile "success evidence was not emitted"
            }
        }
        catch {
            Add-Failure "RETRY_FALLBACK_CONFORMANCE_FAILED" $conformanceFile $_.Exception.Message
        }
    }

    Assert-FileContains $providerBoundaryFile '"implementation": "docs/contracts/retry-fallback/retry-fallback-boundary.v1.json"' "PROVIDER_TO_RETRY_FALLBACK_BINDING_MISSING"
    Assert-FileContains $litellmBoundaryFile '"retry_fallback_mode": "platform_orchestrator"' "LITELLM_RETRY_FALLBACK_OWNERSHIP_INVALID"
    Assert-FileContains $bindingFile '"retry_fallback_boundary": "docs/contracts/retry-fallback/retry-fallback-boundary.v1.json"' "RETRY_FALLBACK_GATEWAY_BINDING_MISSING"
    Assert-FileContains $snapshotSchemaFile '"$ref": "urn:enterprise-ai-platform:retry-fallback:plan:v1"' "RETRY_FALLBACK_SNAPSHOT_BINDING_MISSING"
    Assert-FileContains "docs/contracts/retry-fallback/README.md" "must not synchronously query Control Plane PostgreSQL" "RETRY_FALLBACK_CP_DP_GUARD_MISSING"
    Assert-FileContains "docs/contracts/retry-fallback/README.md" "TBD-008" "RETRY_FALLBACK_ERROR_SCHEMA_TBD_MISSING"
    Assert-FileContains "docs/contracts/retry-fallback/README.md" "TBD-017" "RETRY_FALLBACK_FAILURE_POLICY_TBD_MISSING"
    Assert-FileContains "docs/contracts/retry-fallback/README.md" "eligible_provider_ids" "RETRY_FALLBACK_ROUTER_ELIGIBILITY_GUARD_MISSING"
    Assert-FileContains "docs/contracts/retry-fallback/README.md" "STREAM_RETRY_POLICY_UNRESOLVED" "RETRY_FALLBACK_STREAMING_ADR_MISSING"
    Assert-FileContains "packages/telemetry/README.md" "Retry/Fallback telemetry contract" "RETRY_FALLBACK_TELEMETRY_PACKAGE_BINDING_MISSING"
    Assert-FileContains $workflow "Verify Retry Fallback Boundary" "CI_RETRY_FALLBACK_TEST_MISSING"
    Assert-FileContains $workflow "test-m2-006" "CI_RETRY_FALLBACK_COMMAND_MISSING"
}

function Invoke-UsageEventTest {
    $envelopeSchemaFile = "docs/contracts/events/event-envelope.v1.schema.json"
    $eventSchemaFile = "docs/contracts/events/usage/usage-event.v1.schema.json"
    $processingSchemaFile = "docs/contracts/events/usage/usage-processing-result.v1.schema.json"
    $boundaryFile = "docs/contracts/events/usage/usage-event-boundary.v1.json"
    $baselineFile = "docs/contracts/events/usage/usage-event-compatibility-baseline.v1.json"
    $conformanceFile = "apps/billing/usage-event.conformance.ps1"
    $retryBoundaryFile = "docs/contracts/retry-fallback/retry-fallback-boundary.v1.json"
    $bindingFile = "apps/gateway/contracts/chat-completions.binding.v1.json"
    $usageTbdFile = "packages/db/migrations/TBD.md"
    $workflow = ".github/workflows/pr-gates.yml"

    foreach ($file in @($envelopeSchemaFile, $eventSchemaFile, $processingSchemaFile, $boundaryFile, $baselineFile, $conformanceFile, $retryBoundaryFile, $bindingFile, $usageTbdFile)) {
        Assert-File $file
    }

    try {
        $envelopeSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $envelopeSchemaFile) | ConvertFrom-Json
        $eventSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $eventSchemaFile) | ConvertFrom-Json
        $processingSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $processingSchemaFile) | ConvertFrom-Json
        $boundary = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $boundaryFile) | ConvertFrom-Json
        $baseline = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $baselineFile) | ConvertFrom-Json

        $payloadSchema = $eventSchema.'$defs'.payload
        if ($envelopeSchema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema" -or
            $envelopeSchema.'$id' -ne "urn:enterprise-ai-platform:event-envelope:v1" -or
            $envelopeSchema.additionalProperties -ne $false -or
            $eventSchema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema" -or
            $processingSchema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema" -or
            $processingSchema.additionalProperties -ne $false -or
            $payloadSchema.additionalProperties -ne $false) {
            Add-Failure "USAGE_EVENT_SCHEMA_INVALID" $eventSchemaFile "Usage v1 must extend the closed Event Envelope and publish closed payload/result schemas"
        }
        if ($baseline.baseline_version -ne 1 -or
            $baseline.event_schema_id -ne $eventSchema.'$id' -or
            $baseline.processing_result_schema_id -ne $processingSchema.'$id' -or
            $eventSchema.allOf[0].'$ref' -ne $envelopeSchema.'$id') {
            Add-Failure "USAGE_EVENT_COMPATIBILITY_BASELINE_INVALID" $baselineFile "baseline and Usage event must bind the published Event Envelope and Usage v1 schema IDs"
        }

        $requiredUsageEnvelopeFields = @($envelopeSchema.required) + @($eventSchema.allOf[1].required)
        foreach ($field in @($baseline.required_envelope_fields)) {
            if ($requiredUsageEnvelopeFields -notcontains $field) {
                Add-Failure "USAGE_EVENT_BREAKING_ENVELOPE_FIELD_REMOVAL" $envelopeSchemaFile ("baseline field was removed: " + $field)
            }
        }
        foreach ($field in @($baseline.required_payload_fields)) {
            if (@($payloadSchema.required) -notcontains $field) {
                Add-Failure "USAGE_EVENT_BREAKING_PAYLOAD_FIELD_REMOVAL" $eventSchemaFile ("baseline field was removed: " + $field)
            }
        }
        foreach ($field in @($baseline.required_processing_result_fields)) {
            if (@($processingSchema.required) -notcontains $field) {
                Add-Failure "USAGE_EVENT_BREAKING_RESULT_FIELD_REMOVAL" $processingSchemaFile ("baseline field was removed: " + $field)
            }
        }
        foreach ($outcome in @("succeeded", "failed", "indeterminate")) {
            if (@($payloadSchema.properties.request_outcome.enum) -notcontains $outcome -or @($baseline.required_request_outcomes) -notcontains $outcome) {
                Add-Failure "USAGE_EVENT_REQUEST_OUTCOME_MISSING" $eventSchemaFile ("published request outcome is absent: " + $outcome)
            }
        }
        foreach ($stage in @("enqueue", "publish", "consume")) {
            if (@($processingSchema.properties.stage.enum) -notcontains $stage -or @($baseline.required_processing_stages) -notcontains $stage) {
                Add-Failure "USAGE_EVENT_PROCESSING_STAGE_MISSING" $processingSchemaFile ("published processing stage is absent: " + $stage)
            }
        }
        foreach ($outcome in @("accepted", "published", "processed", "duplicate", "rejected", "failed")) {
            if (@($processingSchema.properties.outcome.enum) -notcontains $outcome -or @($baseline.required_processing_outcomes) -notcontains $outcome) {
                Add-Failure "USAGE_EVENT_PROCESSING_OUTCOME_MISSING" $processingSchemaFile ("published processing outcome is absent: " + $outcome)
            }
        }
        foreach ($action in @("none", "retry", "dead_letter")) {
            if (@($processingSchema.properties.next_action.enum) -notcontains $action -or @($baseline.required_next_actions) -notcontains $action) {
                Add-Failure "USAGE_EVENT_NEXT_ACTION_MISSING" $processingSchemaFile ("published consumer action is absent: " + $action)
            }
        }

        $specializedProperties = $eventSchema.allOf[1].properties
        if ($specializedProperties.event_type.const -ne "UsageObserved" -or
            $specializedProperties.schema_version.const -ne 1 -or
            $specializedProperties.tenant_id.type -ne "string" -or
            $specializedProperties.request_id.type -ne "string" -or
            $specializedProperties.trace_id.type -ne "string" -or
            $specializedProperties.producer.const -ne "gateway-data-plane" -or
            $payloadSchema.properties.token_usage.additionalProperties -ne $false -or
            $payloadSchema.properties.cost.additionalProperties -ne $false) {
            Add-Failure "USAGE_EVENT_ENVELOPE_SPECIALIZATION_INVALID" $eventSchemaFile "UsageObserved must be a tenant/request/trace-scoped, body-free Gateway event with closed token and cost observations"
        }
        foreach ($status in @("reported", "unavailable")) {
            if (@($payloadSchema.properties.token_usage.properties.status.enum) -notcontains $status) {
                Add-Failure "USAGE_EVENT_TOKEN_STATUS_MISSING" $eventSchemaFile ("token observation status is absent: " + $status)
            }
        }
        foreach ($status in @("calculated", "not_calculated")) {
            if (@($payloadSchema.properties.cost.properties.status.enum) -notcontains $status) {
                Add-Failure "USAGE_EVENT_COST_STATUS_MISSING" $eventSchemaFile ("cost observation status is absent: " + $status)
            }
        }

        if ($boundary.status -ne "implemented-v1" -or
            $boundary.event_type -ne "UsageObserved" -or
            $boundary.producer -ne "gateway-data-plane" -or
            $boundary.online_enqueue_mode -ne "non_blocking_try_enqueue" -or
            $boundary.delivery_contract -ne "at_least_once_consumer_idempotency_required" -or
            $null -ne $boundary.producer_method_signature -or
            $boundary.producer_method_signature_status -ne "TBD-001/TBD-002" -or
            $null -ne $boundary.broker_product -or
            $null -ne $boundary.topic_name -or
            $null -ne $boundary.partition_key -or
            $null -ne $boundary.producer_buffer_durability -or
            $null -ne $boundary.backpressure_overflow_policy -or
            $null -ne $boundary.publisher_retry_policy -or
            $null -ne $boundary.dlq_policy -or
            @($boundary.consumer_failure_contract.supported_actions) -notcontains "retry" -or
            @($boundary.consumer_failure_contract.supported_actions) -notcontains "dead_letter" -or
            $null -ne $boundary.consumer_failure_contract.retry_schedule -or
            $null -ne $boundary.consumer_failure_contract.maximum_attempts -or
            $null -ne $boundary.consumer_failure_contract.dlq_destination -or
            $null -ne $boundary.billing_consumer_store -or
            $null -ne $boundary.cost_precision_and_currency_policy) {
            Add-Failure "USAGE_EVENT_TBD_OR_ASYNC_BOUNDARY_INVALID" $boundaryFile "online enqueue must be non-blocking while runtime, transport, storage, retry/DLQ, and cost policies remain unresolved"
        }
        foreach ($metric in @("usage_event_enqueue_total", "usage_event_publish_total", "usage_event_consume_total", "usage_event_backlog")) {
            if (@($boundary.telemetry_projection.metrics) -notcontains $metric) {
                Add-Failure "USAGE_EVENT_METRIC_MISSING" $boundaryFile ("required telemetry projection is absent: " + $metric)
            }
        }
        foreach ($label in @("event_id", "usage_record_id", "request_id", "trace_id", "user_id")) {
            if (@($boundary.telemetry_projection.forbidden_metric_labels) -notcontains $label) {
                Add-Failure "USAGE_EVENT_HIGH_CARDINALITY_GUARD_MISSING" $boundaryFile ("forbidden metric label guard is absent: " + $label)
            }
        }
        foreach ($dependency in @("control_plane_postgresql", "usage_postgresql", "billing_postgresql", "audit_postgresql", "analytics_store", "broker_ack_wait")) {
            if (@($boundary.forbidden_online_dependencies) -notcontains $dependency) {
                Add-Failure "USAGE_EVENT_ONLINE_DEPENDENCY_GUARD_MISSING" $boundaryFile ("forbidden online dependency is absent: " + $dependency)
            }
        }
        $payloadProperties = @($payloadSchema.properties.PSObject.Properties.Name)
        $processingProperties = @($processingSchema.properties.PSObject.Properties.Name)
        foreach ($field in @("endpoint", "secret_ref", "provider_model", "provider_key", "credential", "prompt", "messages", "response", "response_body", "raw_error", "stack_trace")) {
            if (@($boundary.forbidden_fields) -notcontains $field -or $payloadProperties -contains $field -or $processingProperties -contains $field) {
                Add-Failure "USAGE_EVENT_FORBIDDEN_FIELD_GUARD_INVALID" $boundaryFile ("secret/body/internal field guard is invalid: " + $field)
            }
        }
    }
    catch {
        Add-Failure "USAGE_EVENT_CONTRACT_JSON_INVALID" $boundaryFile $_.Exception.Message
    }

    $conformancePath = Join-Path $repoRoot $conformanceFile
    if (Test-Path -LiteralPath $conformancePath -PathType Leaf) {
        try {
            $output = @(& $conformancePath)
            foreach ($line in $output) { Write-Output $line }
            if ($output -notcontains "status=pass reason_code=USAGE_EVENT_CONFORMANCE_OK") {
                Add-Failure "USAGE_EVENT_CONFORMANCE_FAILED" $conformanceFile "success evidence was not emitted"
            }
        }
        catch {
            Add-Failure "USAGE_EVENT_CONFORMANCE_FAILED" $conformanceFile $_.Exception.Message
        }
    }

    Assert-FileContains $retryBoundaryFile '"status": "implemented-v1"' "RETRY_FALLBACK_TO_USAGE_STATUS_MISSING"
    Assert-FileContains $retryBoundaryFile '"contract": "docs/contracts/events/usage/usage-event-boundary.v1.json"' "RETRY_FALLBACK_TO_USAGE_CONTRACT_MISSING"
    Assert-FileContains $bindingFile '"usage_event_boundary": "docs/contracts/events/usage/usage-event-boundary.v1.json"' "USAGE_EVENT_GATEWAY_BINDING_MISSING"
    Assert-FileContains $bindingFile '"usage_event_async_required": true' "USAGE_EVENT_GATEWAY_ASYNC_GUARD_MISSING"
    Assert-FileContains "docs/contracts/events/usage/README.md" "does not synchronously insert into the PostgreSQL Outbox" "USAGE_EVENT_SYNC_OUTBOX_GUARD_MISSING"
    Assert-FileContains "docs/contracts/events/usage/README.md" "deduplicate" "USAGE_EVENT_IDEMPOTENCY_DOC_MISSING"
    Assert-FileContains "apps/billing/README.md" "Billing SQL write" "USAGE_EVENT_BILLING_SYNC_WRITE_GUARD_MISSING"
    Assert-FileContains $usageTbdFile "Event-derived aggregation keys" "USAGE_EVENT_STORAGE_SCHEMA_TBD_MISSING"
    Assert-FileContains $workflow "Verify Usage Event Boundary" "CI_USAGE_EVENT_TEST_MISSING"
    Assert-FileContains $workflow "test-m2-007" "CI_USAGE_EVENT_COMMAND_MISSING"
}

function Invoke-ProductionImageTest {
    $boundaryFile = "deploy/images/gateway/production-image-boundary.v1.json"
    $conformanceFile = "deploy/images/gateway/production-image.conformance.ps1"
    $workflow = ".github/workflows/pr-gates.yml"

    Assert-Directory "deploy/images"
    Assert-Directory "deploy/images/gateway"
    Assert-File "deploy/images/README.md"
    Assert-File "deploy/images/gateway/README.md"
    Assert-File $boundaryFile
    Assert-File $conformanceFile

    Assert-FileContains "deploy/images/README.md" "TBD-001" "PRODUCTION_IMAGE_RUNTIME_TBD_MISSING"
    Assert-FileContains "deploy/images/gateway/README.md" "AC-BLD-001" "PRODUCTION_IMAGE_ACCEPTANCE_BOUNDARY_MISSING"
    Assert-FileContains "deploy/images/gateway/README.md" "previously verified immutable image digest" "PRODUCTION_IMAGE_ROLLBACK_MISSING"
    Assert-FileContains $boundaryFile '"status": "blocked-tbd-001"' "PRODUCTION_IMAGE_BLOCKER_STATUS_MISSING"
    Assert-FileContains $boundaryFile '"image_tag_format_status": "TBD-013"' "PRODUCTION_IMAGE_TAG_TBD_MISSING"
    Assert-FileContains $boundaryFile '"sbom_required": true' "PRODUCTION_IMAGE_SBOM_REQUIREMENT_MISSING"
    Assert-FileContains $boundaryFile '"secret_free_layers": true' "PRODUCTION_IMAGE_SECRET_GUARD_MISSING"

    $conformancePath = Join-Path $repoRoot $conformanceFile
    if (Test-Path -LiteralPath $conformancePath -PathType Leaf) {
        try {
            $output = @(& $conformancePath)
            foreach ($line in $output) { Write-Output $line }
            $success = @($output | Where-Object { $_ -like "status=pass reason_code=PRODUCTION_IMAGE_BOUNDARY_GUARD_OK*" })
            if ($success.Count -ne 1) {
                Add-Failure "PRODUCTION_IMAGE_CONFORMANCE_FAILED" $conformanceFile "explicit blocked-state guard evidence was not emitted"
            }
        }
        catch {
            Add-Failure "PRODUCTION_IMAGE_CONFORMANCE_FAILED" $conformanceFile $_.Exception.Message
        }
    }

    Assert-FileContains $workflow "Verify Production Image Boundary" "CI_PRODUCTION_IMAGE_TEST_MISSING"
    Assert-FileContains $workflow "test-m3-001" "CI_PRODUCTION_IMAGE_COMMAND_MISSING"
}

function Invoke-GatewayHelmTest {
    $chartRoot = "deploy/helm/gateway"
    $conformanceFile = "$chartRoot/gateway-chart.conformance.ps1"
    $workflow = ".github/workflows/pr-gates.yml"

    Assert-Directory $chartRoot
    Assert-Directory "$chartRoot/templates"
    foreach ($file in @(
        "README.md",
        "Chart.yaml",
        "values.yaml",
        "values-dev.yaml",
        "values-test.yaml",
        "values-prod.yaml",
        "values.schema.json",
        "templates/_helpers.tpl",
        "templates/deployment.yaml",
        "templates/service.yaml",
        "templates/poddisruptionbudget.yaml",
        "gateway-chart.conformance.ps1"
    )) {
        Assert-File "$chartRoot/$file"
    }

    Assert-FileContains "$chartRoot/values.yaml" "replicaCount: 3" "HELM_GATEWAY_DEFAULT_REPLICAS_MISSING"
    Assert-FileContains "$chartRoot/values.yaml" "cpu: 500m" "HELM_GATEWAY_CPU_REQUEST_MISSING"
    Assert-FileContains "$chartRoot/values.yaml" "memory: 512Mi" "HELM_GATEWAY_MEMORY_REQUEST_MISSING"
    Assert-FileContains "$chartRoot/values.yaml" "memory: 2Gi" "HELM_GATEWAY_MEMORY_LIMIT_MISSING"
    Assert-FileContains "$chartRoot/templates/deployment.yaml" "containerPort: 8080" "HELM_GATEWAY_PORT_MISSING"
    Assert-FileContains "$chartRoot/templates/deployment.yaml" "readinessProbe:" "HELM_GATEWAY_READINESS_MISSING"
    Assert-FileContains "$chartRoot/templates/deployment.yaml" "livenessProbe:" "HELM_GATEWAY_LIVENESS_MISSING"
    Assert-FileContains "$chartRoot/templates/deployment.yaml" "startupProbe:" "HELM_GATEWAY_STARTUP_MISSING"
    Assert-FileContains "$chartRoot/templates/deployment.yaml" "topologySpreadConstraints:" "HELM_GATEWAY_TOPOLOGY_MISSING"
    Assert-FileContains "$chartRoot/templates/poddisruptionbudget.yaml" "kind: PodDisruptionBudget" "HELM_GATEWAY_PDB_MISSING"
    Assert-FileContains "$chartRoot/README.md" "TBD-019" "HELM_PRODUCTION_LOCATION_TBD_MISSING"
    Assert-FileContains "$chartRoot/README.md" "previously verified immutable image digest" "HELM_ROLLBACK_DIGEST_MISSING"
    Assert-FileContains "deploy/helm/README.md" "remaining later scoped deliverables" "HELM_CHART_SCOPE_BOUNDARY_MISSING"

    $conformancePath = Join-Path $repoRoot $conformanceFile
    if (Test-Path -LiteralPath $conformancePath -PathType Leaf) {
        try {
            $output = @(& $conformancePath)
            foreach ($line in $output) { Write-Output $line }
            $success = @($output | Where-Object { $_ -like "status=pass reason_code=GATEWAY_HELM_CONFORMANCE_OK*" })
            if ($success.Count -ne 1) {
                Add-Failure "GATEWAY_HELM_CONFORMANCE_FAILED" $conformanceFile "Helm lint/template success evidence was not emitted"
            }
        }
        catch {
            Add-Failure "GATEWAY_HELM_CONFORMANCE_FAILED" $conformanceFile $_.Exception.Message
        }
    }

    Assert-FileContains $workflow "azure/setup-helm@9bc31f4ebc9c6b171d7bfbaa5d006ae7abdb4310" "CI_HELM_SETUP_NOT_PINNED"
    Assert-FileContains $workflow "version: v3.21.3" "CI_HELM_VERSION_NOT_PINNED"
    Assert-FileContains $workflow "Verify Gateway Helm Chart" "CI_GATEWAY_HELM_TEST_MISSING"
    Assert-FileContains $workflow "test-m3-002" "CI_GATEWAY_HELM_COMMAND_MISSING"
}

function Invoke-TerraformSkeletonTest {
    $terraformRoot = "deploy/terraform"
    $conformanceFile = "$terraformRoot/terraform.conformance.ps1"
    $workflow = ".github/workflows/pr-gates.yml"
    $modules = @("network", "kubernetes", "postgres", "redis", "kafka", "object-storage", "kms", "dns")
    $environments = @("dev", "stage", "prod")

    Assert-Directory "$terraformRoot/modules"
    Assert-Directory "$terraformRoot/modules/platform-environment"
    Assert-Directory "$terraformRoot/environments"
    Assert-Directory "$terraformRoot/tests"
    Assert-File "$terraformRoot/README.md"
    Assert-File "$terraformRoot/modules/platform-environment/main.tf"
    Assert-File "$terraformRoot/modules/platform-environment/README.md"
    Assert-File "$terraformRoot/tests/README.md"
    Assert-File "$terraformRoot/tests/valid-configuration.tfvars.json"
    Assert-File $conformanceFile

    foreach ($module in $modules) {
        Assert-Directory "$terraformRoot/modules/$module"
        Assert-File "$terraformRoot/modules/$module/main.tf"
        Assert-File "$terraformRoot/modules/$module/README.md"
    }
    foreach ($environment in $environments) {
        Assert-Directory "$terraformRoot/environments/$environment"
        foreach ($file in @("main.tf", "variables.tf", "outputs.tf", "README.md")) {
            Assert-File "$terraformRoot/environments/$environment/$file"
        }
        Assert-FileContains "$terraformRoot/environments/$environment/main.tf" ("environment   = `"$environment`"") "TERRAFORM_ENVIRONMENT_IDENTITY_MISSING"
    }

    Assert-FileContains "$terraformRoot/README.md" "TBD-011" "TERRAFORM_CLOUD_PROVIDER_TBD_MISSING"
    Assert-FileContains "$terraformRoot/README.md" "TBD-012" "TERRAFORM_SECRET_MANAGER_TBD_MISSING"
    Assert-FileContains "$terraformRoot/README.md" 'Passing `terraform validate` proves the' "TERRAFORM_VALIDATION_SCOPE_UNCLEAR"
    Assert-FileContains "$terraformRoot/modules/kubernetes/main.tf" '"data-plane"' "TERRAFORM_DATA_PLANE_NODE_POOL_MISSING"
    Assert-FileContains "$terraformRoot/modules/kubernetes/main.tf" '"runtime"' "TERRAFORM_RUNTIME_NODE_POOL_MISSING"
    Assert-FileContains "$terraformRoot/modules/redis/main.tf" 'cache_key_isolation' "TERRAFORM_REDIS_ISOLATION_MISSING"
    Assert-FileContains "$terraformRoot/modules/kafka/main.tf" 'dead_letter_topic' "TERRAFORM_KAFKA_DLQ_MISSING"
    Assert-FileContains "$terraformRoot/modules/object-storage/main.tf" 'gateway_direct_rag_access = false' "TERRAFORM_RAG_BOUNDARY_MISSING"
    Assert-FileContains "$terraformRoot/modules/kms/main.tf" 'key_material_in_terraform' "TERRAFORM_KEY_MATERIAL_GUARD_MISSING"
    Assert-FileContains "$terraformRoot/environments/prod/README.md" "destructive state edits" "TERRAFORM_ROLLBACK_GUARD_MISSING"

    $conformancePath = Join-Path $repoRoot $conformanceFile
    if (Test-Path -LiteralPath $conformancePath -PathType Leaf) {
        try {
            $output = @(& $conformancePath)
            foreach ($line in $output) { Write-Output $line }
            $success = @($output | Where-Object { $_ -like "status=pass reason_code=TERRAFORM_SKELETON_CONFORMANCE_OK*" })
            if ($success.Count -ne 1) {
                Add-Failure "TERRAFORM_SKELETON_CONFORMANCE_FAILED" $conformanceFile "fmt/init/validate/plan success evidence was not emitted"
            }
        }
        catch {
            Add-Failure "TERRAFORM_SKELETON_CONFORMANCE_FAILED" $conformanceFile $_.Exception.Message
        }
    }

    Assert-FileContains $workflow "hashicorp/setup-terraform@dfe3c3f87815947d99a8997f908cb6525fc44e9e" "CI_TERRAFORM_SETUP_NOT_PINNED"
    Assert-FileContains $workflow "terraform_version: 1.15.8" "CI_TERRAFORM_VERSION_NOT_PINNED"
    Assert-FileContains $workflow "Verify Terraform Skeleton" "CI_TERRAFORM_TEST_MISSING"
    Assert-FileContains $workflow "test-m3-003" "CI_TERRAFORM_COMMAND_MISSING"
}

switch ($Command) {
    "lint" {
        Invoke-Lint
    }
    "test" {
        Invoke-Test
    }
    "test-m0-002" {
        Invoke-ContractDirectoryTest
    }
    "test-m0-003" {
        Invoke-CISkeletonTest
    }
    "test-m1-001" {
        Invoke-MigrationTest
    }
    "test-m1-002" {
        Invoke-MigrationTest
        Invoke-OutboxTest
    }
    "test-m1-003" {
        Invoke-SnapshotStoreTest
    }
    "test-m1-004" {
        Invoke-SnapshotConsumerTest
    }
    "test-m2-001" {
        Invoke-OpenApiContractTest
    }
    "test-m2-002" {
        Invoke-OpenApiContractTest
        Invoke-AuthenticationBoundaryTest
    }
    "test-m2-003" {
        Invoke-OpenApiContractTest
        Invoke-AuthenticationBoundaryTest
        Invoke-PolicyDecisionTest
    }
    "test-m2-004" {
        Invoke-OpenApiContractTest
        Invoke-AuthenticationBoundaryTest
        Invoke-PolicyDecisionTest
        Invoke-RouterPluginTest
    }
    "test-m2-005" {
        Invoke-OpenApiContractTest
        Invoke-AuthenticationBoundaryTest
        Invoke-PolicyDecisionTest
        Invoke-RouterPluginTest
        Invoke-ProviderAdapterTest
    }
    "test-m2-006" {
        Invoke-OpenApiContractTest
        Invoke-AuthenticationBoundaryTest
        Invoke-PolicyDecisionTest
        Invoke-RouterPluginTest
        Invoke-ProviderAdapterTest
        Invoke-RetryFallbackTest
    }
    "test-m2-007" {
        Invoke-OpenApiContractTest
        Invoke-AuthenticationBoundaryTest
        Invoke-PolicyDecisionTest
        Invoke-RouterPluginTest
        Invoke-ProviderAdapterTest
        Invoke-RetryFallbackTest
        Invoke-UsageEventTest
    }
    "test-m3-001" {
        Invoke-ProductionImageTest
    }
    "test-m3-002" {
        Invoke-GatewayHelmTest
    }
    "test-m3-003" {
        Invoke-TerraformSkeletonTest
    }
    "security" {
        Invoke-Security
    }
    "build" {
        Invoke-Lint
        Invoke-Test
        if ($script:Failures.Count -eq 0) {
            Write-Output "status=info command=build reason_code=NO_APPLICATION_RUNTIME_BUILD component_count=13 detail=repository and migration assets validated; no buildable application runtime exists yet"
        }
    }
}

if ($script:Failures.Count -gt 0) {
    foreach ($failure in $script:Failures) {
        Write-Output ("status=fail command={0} reason_code={1} subject={2} detail={3}" -f $Command, $failure.ReasonCode, $failure.Subject, $failure.Detail)
    }
    exit 1
}

$successReason = switch ($Command) {
    "lint" { "REPOSITORY_LINT_OK" }
    "test" { "REPOSITORY_CONTRACT_OK" }
    "test-m0-002" { "PUBLIC_CONTRACT_DIRECTORIES_OK" }
    "test-m0-003" { "PR_GATE_SKELETON_OK" }
    "test-m1-001" { "POSTGRESQL_MIGRATION_BASELINE_OK" }
    "test-m1-002" { "TRANSACTIONAL_OUTBOX_BOUNDARY_OK" }
    "test-m1-003" { "REDIS_SNAPSHOT_STORE_OK" }
    "test-m1-004" { "DATA_PLANE_SNAPSHOT_CONSUMER_OK" }
    "test-m2-001" { "OPENAPI_3_1_BASELINE_OK" }
    "test-m2-002" { "AUTHENTICATION_BOUNDARY_OK" }
    "test-m2-003" { "POLICY_DECISION_BOUNDARY_OK" }
    "test-m2-004" { "ROUTER_PLUGIN_BOUNDARY_OK" }
    "test-m2-005" { "PROVIDER_ADAPTER_BOUNDARY_OK" }
    "test-m2-006" { "RETRY_FALLBACK_BOUNDARY_OK" }
    "test-m2-007" { "USAGE_EVENT_BOUNDARY_OK" }
    "test-m3-001" { "PRODUCTION_IMAGE_BOUNDARY_GUARD_OK" }
    "test-m3-002" { "GATEWAY_HELM_CHART_OK" }
    "test-m3-003" { "TERRAFORM_SKELETON_OK" }
    "security" { "BOOTSTRAP_SECRET_SCAN_OK" }
    "build" { "REPOSITORY_BUILD_ENTRY_OK" }
}

Write-Output ("status=pass command={0} reason_code={1}" -f $Command, $successReason)
