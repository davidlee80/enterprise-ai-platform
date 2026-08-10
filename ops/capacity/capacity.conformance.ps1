[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Condition {
    param([bool]$Condition, [string]$ReasonCode)
    if (-not $Condition) { throw $ReasonCode }
}

function Test-NMinusOneScenario {
    param(
        [double]$TargetRps,
        [double]$RemainingCapacityRps,
        [double]$ObservedFallbackAmplification,
        [double]$MaximumFallbackAmplification,
        [bool]$QuotaAvailable,
        [bool]$CorrectnessChecksPassed
    )

    if ($TargetRps -le 0 -or $RemainingCapacityRps -le 0 -or
        $ObservedFallbackAmplification -lt 1 -or $MaximumFallbackAmplification -lt 1) {
        return "CAPACITY_EVIDENCE_INVALID"
    }
    if (-not $QuotaAvailable) { return "PROVIDER_QUOTA_INSUFFICIENT" }
    if (-not $CorrectnessChecksPassed) { return "N_MINUS_ONE_CORRECTNESS_FAILED" }
    if ($ObservedFallbackAmplification -gt $MaximumFallbackAmplification) {
        return "FALLBACK_AMPLIFICATION_EXCEEDED"
    }
    if ($RemainingCapacityRps -lt ($TargetRps * $ObservedFallbackAmplification)) {
        return "N_MINUS_ONE_CAPACITY_INSUFFICIENT"
    }
    return "N_MINUS_ONE_VALIDATED"
}

$schema = Get-Content -LiteralPath (Join-Path $PSScriptRoot "capacity-profile.v1.schema.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$boundary = Get-Content -LiteralPath (Join-Path $PSScriptRoot "capacity-boundary.v1.json") -Raw -Encoding UTF8 | ConvertFrom-Json

Assert-Condition ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema" -and $schema.additionalProperties -eq $false) "CAPACITY_SCHEMA_INVALID"
foreach ($field in @(
    "target_rps", "target_concurrency", "input_token_distribution_ref",
    "output_token_distribution_ref", "ttft_objective_ref",
    "provider_quota_profile_refs", "maximum_fallback_amplification",
    "provider_n_minus_one_scenario_ref", "region_n_minus_one_scenario_ref"
)) {
    Assert-Condition (@($schema.required) -contains $field) "CAPACITY_REQUIRED_DIMENSION_MISSING"
}
Assert-Condition ($null -eq $boundary.current_profile_ref -and $null -eq $boundary.current_evidence_ref) "CAPACITY_PRODUCTION_VALUE_PREMATURELY_SELECTED"
Assert-Condition ($boundary.production_promotion.missing_or_failed_evidence_blocks_promotion -eq $true) "CAPACITY_PROMOTION_FAIL_CLOSED_MISSING"
Assert-Condition ($boundary.configuration_lifecycle.rollback_required -eq $true) "CAPACITY_ROLLBACK_GUARD_MISSING"

# Test-only fixtures prove evaluator behavior; they are not production targets.
Assert-Condition ((Test-NMinusOneScenario 100 125 1.2 1.3 $true $true) -eq "N_MINUS_ONE_VALIDATED") "CAPACITY_PROVIDER_FIXTURE_FAILED"
Assert-Condition ((Test-NMinusOneScenario 100 110 1.2 1.3 $true $true) -eq "N_MINUS_ONE_CAPACITY_INSUFFICIENT") "CAPACITY_SHORTFALL_NOT_DETECTED"
Assert-Condition ((Test-NMinusOneScenario 100 150 1.4 1.3 $true $true) -eq "FALLBACK_AMPLIFICATION_EXCEEDED") "CAPACITY_AMPLIFICATION_NOT_DETECTED"
Assert-Condition ((Test-NMinusOneScenario 100 150 1.2 1.3 $false $true) -eq "PROVIDER_QUOTA_INSUFFICIENT") "CAPACITY_QUOTA_FAILURE_NOT_DETECTED"
Assert-Condition ((Test-NMinusOneScenario 100 150 1.2 1.3 $true $false) -eq "N_MINUS_ONE_CORRECTNESS_FAILED") "CAPACITY_CORRECTNESS_FAILURE_NOT_DETECTED"

Write-Output "status=pass reason_code=CAPACITY_N_MINUS_ONE_MODEL_OK task=TASK-M5-003 production_profile=unconfigured promotion=fail-closed"
