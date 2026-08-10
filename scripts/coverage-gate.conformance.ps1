[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$policyPath = Join-Path $repoRoot "docs/ci/test-coverage-gate.v1.json"
$baselinePath = Join-Path $repoRoot "docs/ci/test-coverage-gate-compatibility-baseline.v1.json"
$gatePath = Join-Path $PSScriptRoot "coverage-gate.ps1"

function Read-ContractJson {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "COVERAGE_GATE_FILE_MISSING: $Path"
    }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$ReasonCode
    )

    if (-not $Condition) {
        throw $ReasonCode
    }
}

$policy = Read-ContractJson $policyPath
$baseline = Read-ContractJson $baselinePath

foreach ($field in @($baseline.required_policy_fields)) {
    Assert-Condition ($null -ne $policy.PSObject.Properties[[string]$field]) "COVERAGE_GATE_POLICY_FIELD_REMOVED"
}
Assert-Condition ($policy.status -eq "threshold-unresolved" -and $policy.decision_status -eq "TBD-009") "COVERAGE_GATE_TBD_STATUS_INVALID"
foreach ($field in @($baseline.required_unresolved_fields)) {
    Assert-Condition ($null -eq $policy.PSObject.Properties[[string]$field].Value) "COVERAGE_GATE_VALUE_PREMATURELY_SELECTED"
}
Assert-Condition ($policy.threshold_input.name -eq $baseline.threshold_input_name) "COVERAGE_GATE_THRESHOLD_INPUT_CHANGED"
Assert-Condition ($policy.observed_input.name -eq $baseline.observed_input_name) "COVERAGE_GATE_OBSERVED_INPUT_CHANGED"
foreach ($property in $baseline.required_behaviors.PSObject.Properties) {
    Assert-Condition ([string]$policy.behavior.PSObject.Properties[$property.Name].Value -eq [string]$property.Value) "COVERAGE_GATE_BEHAVIOR_CHANGED"
}

$selfTestOutput = @(& $gatePath self-test)
foreach ($line in $selfTestOutput) { Write-Output $line }
Assert-Condition ($selfTestOutput -contains "status=pass command=self-test reason_code=COVERAGE_GATE_COMPARISON_OK fixture_threshold_percent=80 production_threshold_percent=unset") "COVERAGE_GATE_SELF_TEST_EVIDENCE_MISSING"

$savedThreshold = $env:COVERAGE_MINIMUM_PERCENT
$savedObserved = $env:COVERAGE_OBSERVED_PERCENT
try {
    Remove-Item Env:COVERAGE_MINIMUM_PERCENT -ErrorAction SilentlyContinue
    Remove-Item Env:COVERAGE_OBSERVED_PERCENT -ErrorAction SilentlyContinue
    $validateOutput = @(& $gatePath validate)
    foreach ($line in $validateOutput) { Write-Output $line }
    Assert-Condition (@($validateOutput | Where-Object { $_ -like "status=pass command=validate reason_code=COVERAGE_THRESHOLD_TBD_NOT_ENFORCED*" }).Count -eq 1) "COVERAGE_GATE_UNCONFIGURED_EVIDENCE_MISSING"
}
finally {
    if ($null -eq $savedThreshold) { Remove-Item Env:COVERAGE_MINIMUM_PERCENT -ErrorAction SilentlyContinue } else { $env:COVERAGE_MINIMUM_PERCENT = $savedThreshold }
    if ($null -eq $savedObserved) { Remove-Item Env:COVERAGE_OBSERVED_PERCENT -ErrorAction SilentlyContinue } else { $env:COVERAGE_OBSERVED_PERCENT = $savedObserved }
}

Write-Output "status=pass reason_code=CONFIGURABLE_COVERAGE_GATE_OK tbd=TBD-009 production_threshold_percent=unset"
