[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("validate", "up", "status")]
    [string]$Command
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$migrationRoot = Join-Path $repoRoot "packages/db/migrations"
$baselinePath = Join-Path $migrationRoot "000001_baseline.up.sql"
$outboxPath = Join-Path $migrationRoot "000002_outbox.up.sql"
$script:ValidationFailures = @()

function Add-ValidationFailure {
    param(
        [string]$ReasonCode,
        [string]$Subject,
        [string]$Detail
    )

    $script:ValidationFailures += [PSCustomObject]@{
        ReasonCode = $ReasonCode
        Subject = $Subject
        Detail = $Detail
    }
}

function Test-FileContains {
    param(
        [string]$Path,
        [string]$ExpectedText,
        [string]$ReasonCode
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-ValidationFailure "MIGRATION_FILE_MISSING" $Path "required migration asset is absent"
        return
    }

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($content.IndexOf($ExpectedText, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        Add-ValidationFailure $ReasonCode $Path ("missing required text: " + $ExpectedText)
    }
}

function Get-OrderedMigrations {
    $migrations = @(Get-ChildItem -LiteralPath $migrationRoot -Filter "*.up.sql" -File | Sort-Object Name)
    foreach ($migration in $migrations) {
        if ($migration.Name -notmatch '^(?<Version>[0-9]{6})_(?<Name>[a-z0-9-]+)\.up\.sql$') {
            Add-ValidationFailure "MIGRATION_FILENAME_INVALID" $migration.Name "expected <six-digit-version>_<name>.up.sql"
        }
    }
    return $migrations
}

function Invoke-Validation {
    $script:ValidationFailures = @()

    if (-not (Test-Path -LiteralPath $migrationRoot -PathType Container)) {
        Add-ValidationFailure "MIGRATION_DIRECTORY_MISSING" "packages/db/migrations" "migration directory is absent"
    }

    $migrations = @(Get-OrderedMigrations)
    $expectedMigrationNames = @("000001_baseline.up.sql", "000002_outbox.up.sql")
    if ($migrations.Count -ne $expectedMigrationNames.Count) {
        Add-ValidationFailure "MIGRATION_SET_UNEXPECTED" "packages/db/migrations" "TASK-M1-002 expects executable versions 000001 and 000002"
    }
    foreach ($expectedMigrationName in $expectedMigrationNames) {
        if ($migrations.Name -notcontains $expectedMigrationName) {
            Add-ValidationFailure "MIGRATION_FILE_MISSING" $expectedMigrationName "required executable migration is absent"
        }
    }

    $requiredBaselineText = @(
        "BEGIN;",
        "CREATE TABLE schema_migration",
        "CREATE TABLE tenant",
        "id UUID PRIMARY KEY",
        "name TEXT NOT NULL",
        "plan TEXT NOT NULL",
        "status TEXT NOT NULL",
        "budget_monthly NUMERIC(18,6)",
        "created_at TIMESTAMPTZ NOT NULL DEFAULT now()",
        "CREATE TABLE provider_endpoint",
        "provider_name TEXT NOT NULL",
        "region TEXT NOT NULL",
        "endpoint TEXT NOT NULL",
        "secret_ref TEXT NOT NULL",
        "config_version BIGINT NOT NULL DEFAULT 1",
        "CREATE TABLE model_route",
        "tenant_id UUID REFERENCES tenant(id)",
        "model_alias TEXT NOT NULL",
        "provider_endpoint_id UUID REFERENCES provider_endpoint(id)",
        "provider_model TEXT NOT NULL",
        "strategy TEXT NOT NULL",
        "VALUES ('000001'",
        ":'migration_hash'",
        "COMMIT;"
    )

    foreach ($expectedText in $requiredBaselineText) {
        Test-FileContains $baselinePath $expectedText "BASELINE_DDL_INCOMPLETE"
    }

    if (Test-Path -LiteralPath $baselinePath -PathType Leaf) {
        $sql = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8
        $tableMatches = [regex]::Matches($sql, '(?im)^\s*CREATE\s+TABLE\s+([a-z_][a-z0-9_]*)')
        $actualTables = @($tableMatches | ForEach-Object { $_.Groups[1].Value })
        $expectedTables = @("schema_migration", "tenant", "provider_endpoint", "model_route")

        foreach ($table in $actualTables) {
            if ($expectedTables -notcontains $table) {
                Add-ValidationFailure "UNCONFIRMED_TABLE_EXECUTABLE" $table "table fields are not confirmed for TASK-M1-001"
            }
        }
        foreach ($table in $expectedTables) {
            if ($actualTables -notcontains $table) {
                Add-ValidationFailure "BASELINE_TABLE_MISSING" $table "required executable table is absent"
            }
        }

    }

    $requiredOutboxText = @(
        "BEGIN;",
        "CREATE TABLE outbox_event",
        "event_id UUID PRIMARY KEY",
        "event_type TEXT NOT NULL",
        "schema_version INT NOT NULL",
        "occurred_at TIMESTAMPTZ NOT NULL",
        "tenant_id UUID REFERENCES tenant(id)",
        "producer TEXT NOT NULL",
        "payload JSONB NOT NULL",
        "attempt_count INT NOT NULL DEFAULT 0",
        "last_reason_code TEXT",
        "CREATE FUNCTION enqueue_outbox_event",
        "CREATE FUNCTION claim_outbox_events",
        "FOR UPDATE SKIP LOCKED",
        "CREATE FUNCTION mark_outbox_event_published",
        "CREATE FUNCTION release_outbox_event",
        "REVOKE ALL ON FUNCTION enqueue_outbox_event",
        "REVOKE ALL ON FUNCTION claim_outbox_events",
        "REVOKE ALL ON FUNCTION mark_outbox_event_published",
        "REVOKE ALL ON FUNCTION release_outbox_event",
        "VALUES ('000002'",
        ":'migration_hash'",
        "COMMIT;"
    )
    foreach ($expectedText in $requiredOutboxText) {
        Test-FileContains $outboxPath $expectedText "OUTBOX_DDL_INCOMPLETE"
    }

    if (Test-Path -LiteralPath $outboxPath -PathType Leaf) {
        $outboxSql = Get-Content -LiteralPath $outboxPath -Raw -Encoding UTF8
        $outboxTableMatches = [regex]::Matches($outboxSql, '(?im)^\s*CREATE\s+TABLE\s+([a-z_][a-z0-9_]*)')
        $outboxTables = @($outboxTableMatches | ForEach-Object { $_.Groups[1].Value })
        if ($outboxTables.Count -ne 1 -or $outboxTables[0] -ne "outbox_event") {
            Add-ValidationFailure "OUTBOX_TABLE_SET_UNEXPECTED" $outboxPath "TASK-M1-002 may add only the outbox_event business table"
        }
    }

    foreach ($migration in $migrations) {
        $migrationSql = Get-Content -LiteralPath $migration.FullName -Raw -Encoding UTF8
        if ($migrationSql -match '(?im)^\s*(DROP|TRUNCATE)\s+') {
            Add-ValidationFailure "DESTRUCTIVE_UP_MIGRATION" $migration.Name "up migrations must be additive"
        }
        if ($migrationSql -match '(?i)(api[_-]?key|provider[_-]?key|secret|token)\s*[:=]\s*["''][A-Za-z0-9_\-]{12,}["'']') {
            Add-ValidationFailure "MIGRATION_PLAINTEXT_SECRET" $migration.Name "possible plaintext credential assignment detected"
        }
    }

    $tbdPath = Join-Path $migrationRoot "TBD.md"
    foreach ($pendingTable in @("user", "role", "api_key", "provider", "provider_capability", "model", "model_mapping", "route_policy", "usage", "audit_event")) {
        Test-FileContains $tbdPath ("``" + $pendingTable + "``") "PENDING_SCHEMA_TBD_MISSING"
    }
    Test-FileContains $tbdPath "TASK-M1-002" "OUTBOX_SCOPE_TRACE_MISSING"

    $migrationReadme = Join-Path $migrationRoot "README.md"
    Test-FileContains $migrationReadme "forward repair" "MIGRATION_ROLLBACK_POLICY_MISSING"
    Test-FileContains $migrationReadme "MIGRATION_CHECKSUM_MISMATCH" "MIGRATION_CHECKSUM_POLICY_MISSING"
    Test-FileContains $migrationReadme "remain TBD" "MIGRATION_TOOL_TBD_MISSING"

    $exampleRoot = Join-Path $migrationRoot "examples/expand-backfill-contract"
    foreach ($example in @("001-expand.sql.example", "002-backfill.sql.example", "003-contract.sql.example")) {
        $examplePath = Join-Path $exampleRoot $example
        if (-not (Test-Path -LiteralPath $examplePath -PathType Leaf)) {
            Add-ValidationFailure "MIGRATION_EXAMPLE_MISSING" $example "expand/backfill/contract example is absent"
        }
    }

    if ($script:ValidationFailures.Count -gt 0) {
        foreach ($failure in $script:ValidationFailures) {
            Write-Output ("status=fail command=validate reason_code={0} subject={1} detail={2}" -f $failure.ReasonCode, $failure.Subject, $failure.Detail)
        }
        return
    }

    Write-Output "status=pass command=validate reason_code=MIGRATION_STATIC_VALIDATION_OK"
}

function Get-PsqlCommand {
    $psql = Get-Command psql -ErrorAction SilentlyContinue
    if ($null -eq $psql) {
        return $null
    }
    return $psql.Source
}

function Test-ConnectionTargetConfigured {
    if ([string]::IsNullOrWhiteSpace($env:PGSERVICE) -and [string]::IsNullOrWhiteSpace($env:PGDATABASE)) {
        return $false
    }
    return $true
}

function Invoke-PsqlScalar {
    param(
        [string]$PsqlCommand,
        [string]$Sql
    )

    $result = @(& $PsqlCommand --no-psqlrc --tuples-only --no-align --set=ON_ERROR_STOP=1 --command $Sql)
    if ($LASTEXITCODE -ne 0) {
        throw "PSQL_COMMAND_FAILED"
    }
    return (($result -join "`n").Trim())
}

function Invoke-Up {
    Invoke-Validation
    if ($script:ValidationFailures.Count -gt 0) {
        exit 1
    }
    if (-not (Test-ConnectionTargetConfigured)) {
        Write-Output "status=fail reason_code=MIGRATION_TARGET_NOT_CONFIGURED detail=set PGSERVICE or standard libpq PGDATABASE connection settings"
        exit 1
    }
    $psql = Get-PsqlCommand
    if ($null -eq $psql) {
        Write-Output "status=fail reason_code=PSQL_NOT_AVAILABLE detail=install a reviewed PostgreSQL client or run the CI integration test"
        exit 1
    }

    $migrations = @(Get-OrderedMigrations)
    foreach ($migration in $migrations) {
        $null = $migration.Name -match '^(?<Version>[0-9]{6})_(?<Name>[a-z0-9-]+)\.up\.sql$'
        $version = $Matches.Version
        $hash = (Get-FileHash -LiteralPath $migration.FullName -Algorithm SHA256).Hash

        try {
            $historyTable = Invoke-PsqlScalar $psql "SELECT COALESCE(to_regclass('public.schema_migration')::text, '');"
            $appliedHash = ""
            if (-not [string]::IsNullOrWhiteSpace($historyTable)) {
                $appliedHash = Invoke-PsqlScalar $psql ("SELECT COALESCE(content_hash, '') FROM schema_migration WHERE version = '" + $version + "';")
            }
        }
        catch {
            Write-Output ("status=fail command=up reason_code=MIGRATION_STATUS_QUERY_FAILED version={0}" -f $version)
            exit 1
        }

        if (-not [string]::IsNullOrWhiteSpace($appliedHash)) {
            if ($appliedHash -ne $hash) {
                Write-Output ("status=fail command=up reason_code=MIGRATION_CHECKSUM_MISMATCH version={0}" -f $version)
                exit 1
            }
            Write-Output ("status=skip command=up reason_code=MIGRATION_ALREADY_APPLIED version={0}" -f $version)
            continue
        }

        & $psql --no-psqlrc --set=ON_ERROR_STOP=1 --set=("migration_hash=" + $hash) --file $migration.FullName
        if ($LASTEXITCODE -ne 0) {
            Write-Output ("status=fail command=up reason_code=MIGRATION_APPLY_FAILED version={0}" -f $version)
            exit 1
        }
        Write-Output ("status=pass command=up reason_code=MIGRATION_APPLIED version={0}" -f $version)
    }
}

function Invoke-Status {
    if (-not (Test-ConnectionTargetConfigured)) {
        Write-Output "status=fail reason_code=MIGRATION_TARGET_NOT_CONFIGURED detail=set PGSERVICE or standard libpq PGDATABASE connection settings"
        exit 1
    }
    $psql = Get-PsqlCommand
    if ($null -eq $psql) {
        Write-Output "status=fail reason_code=PSQL_NOT_AVAILABLE detail=install a reviewed PostgreSQL client or run the CI integration test"
        exit 1
    }

    try {
        $historyTable = Invoke-PsqlScalar $psql "SELECT COALESCE(to_regclass('public.schema_migration')::text, '');"
        if ([string]::IsNullOrWhiteSpace($historyTable)) {
            Write-Output "status=info command=status reason_code=MIGRATION_HISTORY_NOT_FOUND"
            return
        }
        & $psql --no-psqlrc --set=ON_ERROR_STOP=1 --command "SELECT version, description, content_hash, applied_at FROM schema_migration ORDER BY version;"
        if ($LASTEXITCODE -ne 0) {
            throw "PSQL_COMMAND_FAILED"
        }
    }
    catch {
        Write-Output "status=fail command=status reason_code=MIGRATION_STATUS_QUERY_FAILED"
        exit 1
    }
}

switch ($Command) {
    "validate" {
        Invoke-Validation
        if ($script:ValidationFailures.Count -gt 0) {
            exit 1
        }
    }
    "up" {
        Invoke-Up
    }
    "status" {
        Invoke-Status
    }
}

exit 0
