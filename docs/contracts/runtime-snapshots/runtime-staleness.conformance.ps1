[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$contractRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $contractRoot))
$consumerRoot = Join-Path $repoRoot "packages/cache/snapshot-consumer"
$consumerModulePath = Join-Path $consumerRoot "SnapshotConsumer.psm1"
$consumerConformancePath = Join-Path $consumerRoot "snapshot-consumer.conformance.ps1"

function Read-ContractJson {
    param([string]$Name)

    $path = Join-Path $contractRoot $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "RUNTIME_STALENESS_CONTRACT_FILE_MISSING: $path"
    }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Assert-Condition {
    param([bool]$Condition, [string]$ReasonCode)

    if (-not $Condition) {
        throw $ReasonCode
    }
}

function Copy-ContractObject {
    param([object]$Value)

    return $Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json
}

$policySchema = Read-ContractJson "runtime-staleness-policy.v1.schema.json"
$boundary = Read-ContractJson "runtime-staleness-boundary.v1.json"
$baseline = Read-ContractJson "runtime-staleness-compatibility-baseline.v1.json"
$snapshotSchema = Read-ContractJson "runtime-snapshot.v1.schema.json"

Assert-Condition ($policySchema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "RUNTIME_STALENESS_SCHEMA_DRAFT_INVALID"
Assert-Condition ($policySchema.'$id' -eq $baseline.policy_schema_id) "RUNTIME_STALENESS_POLICY_SCHEMA_ID_CHANGED"
Assert-Condition ($policySchema.additionalProperties -eq $false) "RUNTIME_STALENESS_SCHEMA_UNVERSIONED_EXTENSION_ALLOWED"
foreach ($field in @($baseline.required_policy_fields)) {
    Assert-Condition (@($policySchema.required) -contains [string]$field) "RUNTIME_STALENESS_POLICY_FIELD_REMOVED"
}
Assert-Condition ($policySchema.properties.decision_status.const -eq "TBD-016") "RUNTIME_STALENESS_TBD_GUARD_MISSING"
Assert-Condition (@($policySchema.properties.maximum_staleness_seconds.type) -contains "null") "RUNTIME_STALENESS_UNCONFIGURED_THRESHOLD_NOT_SUPPORTED"
Assert-Condition ($policySchema.properties.maximum_staleness_seconds.exclusiveMinimum -eq 0) "RUNTIME_STALENESS_POSITIVE_THRESHOLD_GUARD_MISSING"
Assert-Condition ($snapshotSchema.properties.staleness_policy.'$ref' -eq "urn:enterprise-ai-platform:runtime-snapshot:staleness-policy:v1") "RUNTIME_SNAPSHOT_STALENESS_POLICY_LINK_MISSING"

Assert-Condition ($boundary.status -eq "policy-interface-ready-threshold-unconfigured" -and $boundary.decision_status -eq "TBD-016") "RUNTIME_STALENESS_BOUNDARY_STATUS_INVALID"
foreach ($field in @($baseline.required_unresolved_policy_fields)) {
    Assert-Condition ($null -eq $boundary.current_policy.$field) "RUNTIME_STALENESS_PRODUCTION_VALUE_PREMATURELY_SELECTED"
}
Assert-Condition ($boundary.measurement.source_timestamp -eq "runtime-snapshot-publication-metadata.effective_at" -and
    $boundary.measurement.staleness_formula -eq "max(0, evaluated_at - effective_at)" -and
    $boundary.measurement.threshold_comparison -eq "staleness_seconds > maximum_staleness_seconds" -and
    $boundary.measurement.unconfigured_threshold_behavior -eq "measure-only-no-threshold-decision" -and
    $boundary.measurement.negative_staleness_clamped_to_zero -eq $true) "RUNTIME_STALENESS_MEASUREMENT_CONTRACT_INVALID"
Assert-Condition ($boundary.runtime_binding.configuration_parameter -eq "MaximumStalenessSeconds" -and
    $null -eq $boundary.runtime_binding.default_value -and
    $boundary.runtime_binding.positive_number_required_when_configured -eq $true -and
    $boundary.runtime_binding.tenant_match_required -eq $true -and
    $boundary.runtime_binding.config_version_match_required -eq $true -and
    $boundary.runtime_binding.policy_revision_required -eq $true -and
    $boundary.runtime_binding.consumes_published_snapshot -eq $true -and
    $boundary.runtime_binding.control_plane_postgresql_query_allowed -eq $false -and
    $boundary.runtime_binding.last_valid_snapshot_preserved_on_redis_failure -eq $true) "RUNTIME_STALENESS_RUNTIME_BINDING_INVALID"
Assert-Condition ($null -eq $boundary.threshold_exceeded_behavior.on_stale_policy_ref -and
    $null -eq $boundary.threshold_exceeded_behavior.request_action -and
    $boundary.threshold_exceeded_behavior.evaluation_changes_request_availability -eq $false -and
    $boundary.threshold_exceeded_behavior.status -eq "TBD-017") "RUNTIME_STALENESS_PREMATURE_FAILURE_POLICY_SELECTED"
Assert-Condition ($boundary.configuration_lifecycle.versioned -eq $true -and
    $boundary.configuration_lifecycle.revision_required -eq $true -and
    $boundary.configuration_lifecycle.rollback_target_required -eq $true -and
    $boundary.configuration_lifecycle.last_valid_policy_preserved_on_publish_failure -eq $true) "RUNTIME_STALENESS_ROLLBACK_GUARD_MISSING"
Assert-Condition (@($boundary.change_evidence.who_fields) -contains "updated_by" -and
    $boundary.change_evidence.revision_field -eq "revision" -and
    @($boundary.change_evidence.impact_scope_fields) -contains "tenant_id" -and
    @($boundary.change_evidence.impact_scope_fields) -contains "config_version" -and
    $boundary.change_evidence.rollback_revision_field -eq "rollback_revision") "RUNTIME_STALENESS_CHANGE_EVIDENCE_MISSING"
foreach ($metricField in @($baseline.required_metric_fields)) {
    Assert-Condition (@($boundary.telemetry.required_fields) -contains [string]$metricField) "RUNTIME_STALENESS_METRIC_FIELD_REMOVED"
}
foreach ($forbiddenField in @($baseline.forbidden_metric_fields)) {
    Assert-Condition (@($boundary.telemetry.high_cardinality_labels_forbidden) -contains [string]$forbiddenField -or
        @("prompt", "response_body", "secret_ref", "credential") -contains [string]$forbiddenField) "RUNTIME_STALENESS_TELEMETRY_SAFETY_GUARD_MISSING"
}

Import-Module $consumerModulePath -Force
$unconfiguredConsumer = New-RuntimeSnapshotConsumer
Assert-Condition ($null -eq $unconfiguredConsumer.MaximumStalenessSeconds -and $null -eq $unconfiguredConsumer.OnStale) "RUNTIME_STALENESS_IMPLICIT_DEFAULT_FOUND"

# The threshold below is a conformance fixture, not a production default or recommendation.
$fixturePolicy = [PSCustomObject]@{
    tenant_id = "tenant-fixture"
    config_version = 23
    revision = 4
    maximum_staleness_seconds = 7
    on_stale_policy_ref = $null
    decision_status = "TBD-016"
}
$configuredResult = New-RuntimeSnapshotConsumerFromStalenessPolicy $fixturePolicy "tenant-fixture" 23
Assert-Condition ($configuredResult.ok -eq $true -and
    $configuredResult.reason_code -eq "STALENESS_THRESHOLD_CONFIGURED" -and
    $configuredResult.consumer.MaximumStalenessSeconds -eq 7 -and
    $null -eq $configuredResult.consumer.OnStale) "RUNTIME_STALENESS_CONFIGURED_BINDING_FAILED"

$unconfiguredPolicy = Copy-ContractObject $fixturePolicy
$unconfiguredPolicy.maximum_staleness_seconds = $null
$unconfiguredResult = New-RuntimeSnapshotConsumerFromStalenessPolicy $unconfiguredPolicy "tenant-fixture" 23
Assert-Condition ($unconfiguredResult.ok -eq $true -and
    $unconfiguredResult.reason_code -eq "STALENESS_THRESHOLD_UNCONFIGURED" -and
    $null -eq $unconfiguredResult.consumer.MaximumStalenessSeconds) "RUNTIME_STALENESS_UNCONFIGURED_POLICY_ENFORCED"

$tenantMismatchResult = New-RuntimeSnapshotConsumerFromStalenessPolicy $fixturePolicy "tenant-other" 23
Assert-Condition ($tenantMismatchResult.ok -eq $false -and $tenantMismatchResult.reason_code -eq "STALENESS_POLICY_TENANT_MISMATCH") "RUNTIME_STALENESS_TENANT_MISMATCH_ACCEPTED"
$tenantInvalidResult = New-RuntimeSnapshotConsumerFromStalenessPolicy $fixturePolicy " " 23
Assert-Condition ($tenantInvalidResult.ok -eq $false -and $tenantInvalidResult.reason_code -eq "STALENESS_POLICY_TENANT_INVALID") "RUNTIME_STALENESS_INVALID_TENANT_ACCEPTED"
$versionMismatchResult = New-RuntimeSnapshotConsumerFromStalenessPolicy $fixturePolicy "tenant-fixture" 24
Assert-Condition ($versionMismatchResult.ok -eq $false -and $versionMismatchResult.reason_code -eq "STALENESS_POLICY_CONFIG_VERSION_MISMATCH") "RUNTIME_STALENESS_CONFIG_VERSION_MISMATCH_ACCEPTED"
$revisionInvalidPolicy = Copy-ContractObject $fixturePolicy
$revisionInvalidPolicy.revision = 0
$revisionInvalidResult = New-RuntimeSnapshotConsumerFromStalenessPolicy $revisionInvalidPolicy "tenant-fixture" 23
Assert-Condition ($revisionInvalidResult.ok -eq $false -and $revisionInvalidResult.reason_code -eq "STALENESS_POLICY_REVISION_INVALID") "RUNTIME_STALENESS_INVALID_REVISION_ACCEPTED"
$thresholdInvalidPolicy = Copy-ContractObject $fixturePolicy
$thresholdInvalidPolicy.maximum_staleness_seconds = 0
$thresholdInvalidResult = New-RuntimeSnapshotConsumerFromStalenessPolicy $thresholdInvalidPolicy "tenant-fixture" 23
Assert-Condition ($thresholdInvalidResult.ok -eq $false -and $thresholdInvalidResult.reason_code -eq "STALENESS_POLICY_THRESHOLD_INVALID") "RUNTIME_STALENESS_INVALID_THRESHOLD_ACCEPTED"

$consumerOutput = @(& $consumerConformancePath)
foreach ($line in $consumerOutput) { Write-Output $line }
Assert-Condition (@($consumerOutput | Where-Object { $_ -eq "status=pass reason_code=DATA_PLANE_SNAPSHOT_CONSUMER_CONFORMANCE_OK" }).Count -eq 1) "RUNTIME_STALENESS_CONSUMER_REGRESSION"

$consumerModule = Get-Content -LiteralPath $consumerModulePath -Raw -Encoding UTF8
Assert-Condition ($consumerModule.Contains('[object]$MaximumStalenessSeconds = $null')) "RUNTIME_STALENESS_NULL_DEFAULT_MISSING"
Assert-Condition ($consumerModule.Contains('maximum staleness must be a positive number when configured')) "RUNTIME_STALENESS_INVALID_INPUT_GUARD_MISSING"
Assert-Condition (-not $consumerModule.Contains("Npgsql") -and -not $consumerModule.Contains("packages/db")) "RUNTIME_STALENESS_CONTROL_PLANE_DATABASE_DEPENDENCY_FOUND"

Write-Output "status=pass reason_code=RUNTIME_STALENESS_CONFIGURABILITY_OK tbd=TBD-016 maximum_staleness_seconds=unconfigured on_stale=TBD-017"
