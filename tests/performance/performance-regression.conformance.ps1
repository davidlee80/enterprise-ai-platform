[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Condition {
    param([bool]$Condition, [string]$ReasonCode)
    if (-not $Condition) { throw $ReasonCode }
}

function Get-Percentile {
    param([double[]]$Values, [double]$Percentile)
    if ($Values.Count -eq 0 -or $Percentile -lt 0 -or $Percentile -gt 1) {
        throw "PERFORMANCE_OBSERVATION_INVALID"
    }
    $sorted = @($Values | Sort-Object)
    $index = [Math]::Ceiling($Percentile * $sorted.Count) - 1
    return [double]$sorted[[Math]::Max(0, $index)]
}

function Test-Regression {
    param([object]$Profile, [object]$Observation)
    $thresholds = @(
        $Profile.minimum_success_ratio,
        $Profile.maximum_p95_milliseconds,
        $Profile.maximum_p99_milliseconds,
        $Profile.maximum_ttft_milliseconds
    )
    $configured = @($thresholds | Where-Object { $null -ne $_ }).Count
    if ($configured -eq 0) { return "PERFORMANCE_MEASURE_ONLY" }
    if ($configured -ne 4) { return "PERFORMANCE_PROFILE_PARTIAL" }
    if ($Observation.success_ratio -lt $Profile.minimum_success_ratio) { return "PERFORMANCE_SUCCESS_RATIO_FAILED" }
    if ($Observation.p95_milliseconds -gt $Profile.maximum_p95_milliseconds) { return "PERFORMANCE_P95_FAILED" }
    if ($Observation.p99_milliseconds -gt $Profile.maximum_p99_milliseconds) { return "PERFORMANCE_P99_FAILED" }
    if ($Observation.ttft_milliseconds -gt $Profile.maximum_ttft_milliseconds) { return "PERFORMANCE_TTFT_FAILED" }
    return "PERFORMANCE_REGRESSION_PASSED"
}

$schema = Get-Content -LiteralPath (Join-Path $PSScriptRoot "performance-profile.v1.schema.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$boundary = Get-Content -LiteralPath (Join-Path $PSScriptRoot "performance-boundary.v1.json") -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ($schema.additionalProperties -eq $false -and $schema.properties.decision_status.const -eq "TBD-009,TBD-010") "PERFORMANCE_SCHEMA_INVALID"
Assert-Condition ($null -eq $boundary.current_profile_ref -and $null -eq $boundary.current_load_driver_ref -and $null -eq $boundary.current_environment_evidence_ref) "PERFORMANCE_PRODUCTION_VALUE_PREMATURELY_SELECTED"
Assert-Condition ($boundary.threshold_behavior.unconfigured -eq "measure-only-no-release-decision" -and $boundary.threshold_behavior.configured_failure -eq "block-promotion") "PERFORMANCE_GATE_BEHAVIOR_INVALID"

Assert-Condition ((Get-Percentile @(10, 20, 30, 40, 50) 0.95) -eq 50) "PERFORMANCE_PERCENTILE_INVALID"
$unconfigured = [PSCustomObject]@{ minimum_success_ratio = $null; maximum_p95_milliseconds = $null; maximum_p99_milliseconds = $null; maximum_ttft_milliseconds = $null }
$configured = [PSCustomObject]@{ minimum_success_ratio = 0.99; maximum_p95_milliseconds = 100; maximum_p99_milliseconds = 200; maximum_ttft_milliseconds = 80 }
$observation = [PSCustomObject]@{ success_ratio = 1.0; p95_milliseconds = 90; p99_milliseconds = 180; ttft_milliseconds = 70 }
Assert-Condition ((Test-Regression $unconfigured $observation) -eq "PERFORMANCE_MEASURE_ONLY") "PERFORMANCE_UNCONFIGURED_MODE_INVALID"
Assert-Condition ((Test-Regression $configured $observation) -eq "PERFORMANCE_REGRESSION_PASSED") "PERFORMANCE_PASS_FIXTURE_FAILED"
$observation.p99_milliseconds = 220
Assert-Condition ((Test-Regression $configured $observation) -eq "PERFORMANCE_P99_FAILED") "PERFORMANCE_FAILURE_NOT_DETECTED"

Write-Output "status=pass reason_code=PERFORMANCE_REGRESSION_EVALUATOR_OK task=TASK-M4-004 thresholds=unconfigured production_ready=false"
