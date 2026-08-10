[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("validate", "self-test")]
    [string]$Command = "validate",
    [string]$ThresholdPercent,
    [string]$ObservedPercent
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$policyPath = Join-Path $repoRoot "docs/ci/test-coverage-gate.v1.json"

function New-GateResult {
    param(
        [string]$Status,
        [string]$ReasonCode,
        [string]$Enforcement,
        [Nullable[decimal]]$Threshold,
        [Nullable[decimal]]$Observed
    )

    return [PSCustomObject][ordered]@{
        Status = $Status
        ReasonCode = $ReasonCode
        Enforcement = $Enforcement
        Threshold = $Threshold
        Observed = $Observed
    }
}

function Convert-CoveragePercent {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $parsed = [decimal]0
    $valid = [decimal]::TryParse(
        $Value,
        [System.Globalization.NumberStyles]::Number,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$parsed)
    if (-not $valid -or $parsed -lt [decimal]0 -or $parsed -gt [decimal]100) {
        return [PSCustomObject]@{ Invalid = $true }
    }
    return $parsed
}

function Test-CoverageGate {
    param(
        [string]$ThresholdValue,
        [string]$ObservedValue
    )

    if ([string]::IsNullOrWhiteSpace($ThresholdValue)) {
        return New-GateResult "pass" "COVERAGE_THRESHOLD_TBD_NOT_ENFORCED" "not-active" $null $null
    }

    $threshold = Convert-CoveragePercent $ThresholdValue
    if ($threshold -isnot [decimal]) {
        return New-GateResult "fail" "COVERAGE_THRESHOLD_INVALID" "active" $null $null
    }
    if ([string]::IsNullOrWhiteSpace($ObservedValue)) {
        return New-GateResult "fail" "COVERAGE_OBSERVATION_MISSING" "active" $threshold $null
    }
    $observed = Convert-CoveragePercent $ObservedValue
    if ($observed -isnot [decimal]) {
        return New-GateResult "fail" "COVERAGE_OBSERVATION_INVALID" "active" $threshold $null
    }
    if ($observed -lt $threshold) {
        return New-GateResult "fail" "COVERAGE_BELOW_CONFIGURED_THRESHOLD" "active" $threshold $observed
    }
    return New-GateResult "pass" "COVERAGE_AT_OR_ABOVE_CONFIGURED_THRESHOLD" "active" $threshold $observed
}

function Write-GateResult {
    param(
        [object]$Result,
        [string]$CommandName
    )

    $thresholdText = if ($null -eq $Result.Threshold) { "unset" } else { $Result.Threshold.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
    $observedText = if ($null -eq $Result.Observed) { "unset" } else { $Result.Observed.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
    Write-Output ("status={0} command={1} reason_code={2} enforcement={3} threshold_percent={4} observed_percent={5}" -f
        $Result.Status,
        $CommandName,
        $Result.ReasonCode,
        $Result.Enforcement,
        $thresholdText,
        $observedText)
}

if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) {
    Write-Output "status=fail command=$Command reason_code=COVERAGE_GATE_POLICY_MISSING"
    exit 1
}
try {
    $policy = Get-Content -Raw -Encoding UTF8 -LiteralPath $policyPath | ConvertFrom-Json
}
catch {
    Write-Output "status=fail command=$Command reason_code=COVERAGE_GATE_POLICY_INVALID"
    exit 1
}

if ($policy.decision_status -ne "TBD-009" -or
    $policy.status -ne "threshold-unresolved" -or
    $null -ne $policy.threshold_percent -or
    $null -ne $policy.metric -or
    $null -ne $policy.aggregation -or
    $null -ne $policy.collector -or
    $null -ne $policy.report_format) {
    Write-Output "status=fail command=$Command reason_code=COVERAGE_UNREVIEWED_POLICY_SELECTION_DETECTED"
    exit 1
}

if ($Command -eq "self-test") {
    $unconfigured = Test-CoverageGate "" ""
    $missingObservation = Test-CoverageGate "80" ""
    $invalidThreshold = Test-CoverageGate "not-a-number" "80"
    $below = Test-CoverageGate "80" "79.9"
    $equal = Test-CoverageGate "80" "80"
    $above = Test-CoverageGate "80" "80.1"
    if ($unconfigured.ReasonCode -ne "COVERAGE_THRESHOLD_TBD_NOT_ENFORCED" -or
        $missingObservation.ReasonCode -ne "COVERAGE_OBSERVATION_MISSING" -or
        $invalidThreshold.ReasonCode -ne "COVERAGE_THRESHOLD_INVALID" -or
        $below.ReasonCode -ne "COVERAGE_BELOW_CONFIGURED_THRESHOLD" -or
        $equal.Status -ne "pass" -or
        $above.Status -ne "pass") {
        Write-Output "status=fail command=self-test reason_code=COVERAGE_GATE_SELF_TEST_FAILED"
        exit 1
    }
    Write-Output "status=pass command=self-test reason_code=COVERAGE_GATE_COMPARISON_OK fixture_threshold_percent=80 production_threshold_percent=unset"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ThresholdPercent)) {
    $ThresholdPercent = [string]$env:COVERAGE_MINIMUM_PERCENT
}
if ([string]::IsNullOrWhiteSpace($ObservedPercent)) {
    $ObservedPercent = [string]$env:COVERAGE_OBSERVED_PERCENT
}

$result = Test-CoverageGate $ThresholdPercent $ObservedPercent
Write-GateResult $result "validate"
if ($result.Status -ne "pass") {
    exit 1
}
