[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$catalogPath = Join-Path $PSScriptRoot "sli-catalog.v1.json"
$policySchemaPath = Join-Path $PSScriptRoot "slo-target-policy.v1.schema.json"
$dashboardPath = Join-Path $PSScriptRoot "dashboard-model.v1.json"
$boundaryPath = Join-Path $PSScriptRoot "slo-boundary.v1.json"
$baselinePath = Join-Path $PSScriptRoot "slo-compatibility-baseline.v1.json"

function Read-ContractJson {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "SLO_CONTRACT_FILE_MISSING: $Path"
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

$catalog = Read-ContractJson $catalogPath
$policySchema = Read-ContractJson $policySchemaPath
$dashboard = Read-ContractJson $dashboardPath
$boundary = Read-ContractJson $boundaryPath
$baseline = Read-ContractJson $baselinePath

Assert-Condition ($policySchema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "SLO_POLICY_SCHEMA_DRAFT_INVALID"
Assert-Condition ($policySchema.'$id' -eq $baseline.target_policy_schema_id) "SLO_POLICY_SCHEMA_ID_CHANGED"
Assert-Condition ($policySchema.additionalProperties -eq $false) "SLO_POLICY_UNVERSIONED_EXTENSION_ALLOWED"
foreach ($field in @($baseline.required_policy_fields)) {
    Assert-Condition (@($policySchema.required) -contains [string]$field) "SLO_POLICY_FIELD_REMOVED"
}
Assert-Condition ($policySchema.properties.decision_status.const -eq "TBD-010") "SLO_POLICY_TBD_GUARD_MISSING"
foreach ($targetField in @("sli_id", "objective", "measurement_window", "warning_threshold", "critical_threshold", "error_budget_policy")) {
    Assert-Condition (@($policySchema.properties.targets.items.required) -contains $targetField) "SLO_TARGET_POLICY_FIELD_REMOVED"
}
Assert-Condition ($policySchema.properties.targets.items.additionalProperties -eq $false) "SLO_TARGET_POLICY_UNVERSIONED_EXTENSION_ALLOWED"

$catalogIds = @($catalog.indicators.id)
Assert-Condition (@($catalogIds | Sort-Object -Unique).Count -eq $catalogIds.Count) "SLI_CATALOG_DUPLICATE_ID"
Assert-Condition (@($dashboard.panels).Count -eq $catalogIds.Count) "SLO_DASHBOARD_PANEL_SET_CHANGED"
foreach ($sliId in @($baseline.required_sli_ids)) {
    Assert-Condition ($catalogIds -contains [string]$sliId) "SLI_REQUIRED_INDICATOR_MISSING"
    $indicator = @($catalog.indicators | Where-Object { $_.id -eq $sliId })
    Assert-Condition ($indicator.Count -eq 1 -and $null -eq $indicator[0].source_binding -and $indicator[0].target_status -eq "TBD-010") "SLI_SOURCE_OR_TARGET_PREMATURELY_SELECTED"
    $panel = @($dashboard.panels | Where-Object { $_.sli_id -eq $sliId })
    Assert-Condition ($panel.Count -eq 1 -and $panel[0].target_status -eq "TBD-010") "SLO_DASHBOARD_PANEL_MISSING"
    Assert-Condition ($panel[0].source_binding -eq "catalog.indicators.$sliId.source_binding") "SLO_DASHBOARD_SOURCE_BINDING_INVALID"
    Assert-Condition ($panel[0].target_binding -eq "targets.$sliId.objective") "SLO_DASHBOARD_TARGET_BINDING_INVALID"
}

Assert-Condition ($dashboard.status -eq "target-aware-targets-unconfigured" -and $dashboard.decision_status -eq "TBD-010") "SLO_DASHBOARD_STATUS_INVALID"
Assert-Condition ($null -eq $dashboard.data_source_ref -and $null -eq $dashboard.target_policy_ref -and $null -eq $dashboard.alert_target_source -and $null -eq $dashboard.release_gate_target_source) "SLO_DASHBOARD_TARGET_PREMATURELY_BOUND"
Assert-Condition ($boundary.status -eq "dashboard-ready-targets-unconfigured" -and $boundary.decision_status -eq "TBD-010") "SLO_BOUNDARY_STATUS_INVALID"
Assert-Condition ($boundary.configuration_lifecycle.versioned -eq $true -and $boundary.configuration_lifecycle.rollback_required -eq $true) "SLO_VERSION_ROLLBACK_MISSING"
Assert-Condition ($boundary.telemetry_safety.tenant_id_controlled_dimension_only -eq $true) "SLO_TENANT_DIMENSION_GUARD_MISSING"

Assert-Condition ($null -eq $boundary.target_configuration.active_policy_ref -and
    $null -eq $boundary.data_source.binding_ref -and
    $null -eq $boundary.alerting.target_policy_ref -and
    $null -eq $boundary.alerting.burn_rate_windows -and
    $null -eq $boundary.release_gate.target_policy_ref -and
    $null -eq $boundary.release_gate.failure_thresholds) "SLO_TARGET_OR_GATE_PREMATURELY_SELECTED"

foreach ($label in @($baseline.forbidden_metric_labels)) {
    Assert-Condition (@($catalog.forbidden_metric_labels) -contains [string]$label) "SLO_HIGH_CARDINALITY_LABEL_GUARD_REMOVED"
}

$serializedContracts = @($catalog, $dashboard, $boundary) | ConvertTo-Json -Depth 30 -Compress
foreach ($forbiddenNumericCommitment in @('"objective":', '"warning_threshold":', '"critical_threshold":')) {
    Assert-Condition (-not $serializedContracts.Contains($forbiddenNumericCommitment)) "SLO_NUMERIC_TARGET_PREMATURELY_PUBLISHED"
}

Write-Output "status=pass reason_code=CONFIGURABLE_SLO_DASHBOARD_OK tbd=TBD-010 targets=unconfigured data_source=unconfigured"
