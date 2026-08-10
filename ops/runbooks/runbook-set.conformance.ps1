[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$requiredRunbooks = @(
    "control-plane-unavailable.md",
    "redis-unavailable.md",
    "provider-failure.md",
    "configuration-publication-failure.md",
    "database-migration-failure.md",
    "deployment-rollback.md"
)
$requiredSections = @(
    "## Symptom",
    "## Alert",
    "## Impact",
    "## Diagnosis",
    "## Mitigation",
    "## Rollback / failover",
    "## Verification",
    "## Escalation"
)
$forbiddenPatterns = @(
    '(?i)password\s*[:=]',
    '(?i)(api|provider)[_-]?key\s*[:=]',
    '(?i)bearer\s+[a-z0-9_-]{12,}',
    '(?i)kubectl\s+apply'
)

foreach ($runbook in $requiredRunbooks) {
    $path = Join-Path $PSScriptRoot $runbook
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "RUNBOOK_REQUIRED_FILE_MISSING: $runbook"
    }
    $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    foreach ($section in $requiredSections) {
        if ($content.IndexOf($section, [StringComparison]::Ordinal) -lt 0) {
            throw "RUNBOOK_REQUIRED_SECTION_MISSING: $runbook $section"
        }
    }
    foreach ($pattern in $forbiddenPatterns) {
        if ($content -match $pattern) {
            throw "RUNBOOK_FORBIDDEN_CONTENT_FOUND: $runbook"
        }
    }
    if ($content.IndexOf("reason", [StringComparison]::OrdinalIgnoreCase) -lt 0 -or
        $content.IndexOf("revision", [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "RUNBOOK_TRACEABILITY_CONTEXT_MISSING: $runbook"
    }
}

Write-Output "status=pass reason_code=RUNBOOK_SET_OK task=TASK-M5-002 runbooks=6 contacts=opaque thresholds=policy-bound"
