[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$contractRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $contractRoot))

function Read-ContractJson {
    param([string]$Name)

    $path = Join-Path $contractRoot $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "DEPRECATION_CONTRACT_FILE_MISSING: $path"
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

    return $Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json
}

function New-DeprecationEvaluation {
    param(
        [object]$Context,
        [object]$Policy,
        [string]$State,
        [string]$ReasonCode
    )

    $windowStartsAt = $null
    $windowEndsAt = $null
    $replacementRef = $null
    $enforcementRef = $null
    if ($null -ne $Policy) {
        $windowStartsAt = $Policy.window_starts_at
        $windowEndsAt = $Policy.window_ends_at
        $replacementRef = $Policy.replacement_ref
        $enforcementRef = $Policy.enforcement_after_window_ref
    }

    return [PSCustomObject][ordered]@{
        schema_version = 1
        evaluation_id = "evaluation-fixture"
        tenant_id = $Context.tenant_id
        config_version = [int]$Context.config_version
        policy_revision = [int]$Context.policy_revision
        resource_kind = [string]$Context.resource_kind
        resource_ref = [string]$Context.resource_ref
        evaluated_at = [string]$Context.evaluated_at
        state = $State
        reason_code = $ReasonCode
        window_starts_at = $windowStartsAt
        window_ends_at = $windowEndsAt
        replacement_ref = $replacementRef
        enforcement_after_window_ref = $enforcementRef
    }
}

function Invoke-ReferenceDeprecationEvaluation {
    param(
        [object]$Policy,
        [object]$Context
    )

    if ($null -eq $Policy) {
        return New-DeprecationEvaluation $Context $null "unconfigured" "DEPRECATION_POLICY_UNCONFIGURED"
    }
    if ($null -ne $Policy.tenant_id -and [string]$Policy.tenant_id -ne [string]$Context.tenant_id) {
        return New-DeprecationEvaluation $Context $Policy "indeterminate" "DEPRECATION_TENANT_MISMATCH"
    }
    if ([int]$Policy.config_version -ne [int]$Context.config_version) {
        return New-DeprecationEvaluation $Context $Policy "indeterminate" "DEPRECATION_CONFIG_VERSION_MISMATCH"
    }
    if ([int]$Policy.revision -ne [int]$Context.policy_revision) {
        return New-DeprecationEvaluation $Context $Policy "indeterminate" "DEPRECATION_POLICY_REVISION_MISMATCH"
    }
    if ([string]$Policy.resource_kind -ne [string]$Context.resource_kind -or
        [string]$Policy.resource_ref -ne [string]$Context.resource_ref) {
        return New-DeprecationEvaluation $Context $Policy "indeterminate" "DEPRECATION_RESOURCE_MISMATCH"
    }
    if ([string]::IsNullOrWhiteSpace([string]$Policy.window_starts_at) -or
        [string]::IsNullOrWhiteSpace([string]$Policy.window_ends_at)) {
        return New-DeprecationEvaluation $Context $Policy "unconfigured" "DEPRECATION_POLICY_UNCONFIGURED"
    }

    try {
        $evaluatedAt = [DateTimeOffset]::Parse([string]$Context.evaluated_at, [Globalization.CultureInfo]::InvariantCulture)
        $windowStartsAt = [DateTimeOffset]::Parse([string]$Policy.window_starts_at, [Globalization.CultureInfo]::InvariantCulture)
        $windowEndsAt = [DateTimeOffset]::Parse([string]$Policy.window_ends_at, [Globalization.CultureInfo]::InvariantCulture)
        $announcementAt = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$Policy.announcement_at)) {
            $announcementAt = [DateTimeOffset]::Parse([string]$Policy.announcement_at, [Globalization.CultureInfo]::InvariantCulture)
        }
    }
    catch {
        return New-DeprecationEvaluation $Context $Policy "invalid" "DEPRECATION_WINDOW_INVALID"
    }

    if ($windowEndsAt -le $windowStartsAt -or ($null -ne $announcementAt -and $announcementAt -gt $windowStartsAt)) {
        return New-DeprecationEvaluation $Context $Policy "invalid" "DEPRECATION_WINDOW_INVALID"
    }
    if ($evaluatedAt -lt $windowStartsAt) {
        return New-DeprecationEvaluation $Context $Policy "not_started" "DEPRECATION_NOT_STARTED"
    }
    if ($evaluatedAt -lt $windowEndsAt) {
        return New-DeprecationEvaluation $Context $Policy "in_window" "DEPRECATION_WINDOW_ACTIVE"
    }
    return New-DeprecationEvaluation $Context $Policy "window_elapsed" "DEPRECATION_WINDOW_ELAPSED"
}

$policySchema = Read-ContractJson "deprecation-policy.v1.schema.json"
$evaluationSchema = Read-ContractJson "deprecation-evaluation.v1.schema.json"
$boundary = Read-ContractJson "deprecation-boundary.v1.json"
$baseline = Read-ContractJson "deprecation-compatibility-baseline.v1.json"

foreach ($schema in @($policySchema, $evaluationSchema)) {
    Assert-Condition ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "DEPRECATION_SCHEMA_DRAFT_INVALID"
    Assert-Condition ($schema.additionalProperties -eq $false) "DEPRECATION_SCHEMA_UNVERSIONED_EXTENSION_ALLOWED"
}
Assert-Condition ($policySchema.'$id' -eq $baseline.policy_schema_id) "DEPRECATION_POLICY_SCHEMA_ID_CHANGED"
Assert-Condition ($evaluationSchema.'$id' -eq $baseline.evaluation_schema_id) "DEPRECATION_EVALUATION_SCHEMA_ID_CHANGED"
foreach ($field in @($baseline.required_policy_fields)) {
    Assert-Condition (@($policySchema.required) -contains [string]$field) "DEPRECATION_POLICY_FIELD_REMOVED"
}
foreach ($field in @($baseline.required_evaluation_fields)) {
    Assert-Condition (@($evaluationSchema.required) -contains [string]$field) "DEPRECATION_EVALUATION_FIELD_REMOVED"
}
foreach ($resourceKind in @($baseline.required_resource_kinds)) {
    Assert-Condition (@($policySchema.properties.resource_kind.enum) -contains [string]$resourceKind) "DEPRECATION_RESOURCE_KIND_REMOVED"
    Assert-Condition (@($evaluationSchema.properties.resource_kind.enum) -contains [string]$resourceKind) "DEPRECATION_EVALUATION_RESOURCE_KIND_REMOVED"
    Assert-Condition (@($boundary.supported_resource_kinds) -contains [string]$resourceKind) "DEPRECATION_BOUNDARY_RESOURCE_KIND_REMOVED"
}
foreach ($state in @($baseline.required_states)) {
    Assert-Condition (@($evaluationSchema.properties.state.enum) -contains [string]$state) "DEPRECATION_EVALUATION_STATE_REMOVED"
}
foreach ($reasonCode in @($baseline.required_reason_codes)) {
    Assert-Condition (@($evaluationSchema.properties.reason_code.enum) -contains [string]$reasonCode) "DEPRECATION_REASON_CODE_REMOVED"
}
Assert-Condition ($policySchema.properties.decision_status.const -eq "TBD-015") "DEPRECATION_TBD_GUARD_MISSING"
foreach ($nullableField in @("window_starts_at", "window_ends_at", "window_duration", "notification_policy_ref", "enforcement_after_window_ref", "exception_policy_ref")) {
    Assert-Condition (@($policySchema.properties.$nullableField.type) -contains "null") "DEPRECATION_UNCONFIGURED_POLICY_NOT_SUPPORTED"
}

Assert-Condition ($boundary.status -eq "workflow-ready-window-duration-unconfigured" -and $boundary.decision_status -eq "TBD-015") "DEPRECATION_BOUNDARY_STATUS_INVALID"
foreach ($field in @($baseline.required_unresolved_policy_fields)) {
    Assert-Condition ($null -eq $boundary.current_policy.$field) "DEPRECATION_PRODUCTION_VALUE_PREMATURELY_SELECTED"
}
Assert-Condition ($boundary.publication_guard.explicit_window_start_required -eq $true -and
    $boundary.publication_guard.explicit_window_end_required -eq $true -and
    $boundary.publication_guard.window_end_must_follow_start -eq $true -and
    $boundary.publication_guard.window_boundary_semantics -eq "start-inclusive-end-exclusive" -and
    $boundary.publication_guard.announcement_must_not_follow_start -eq $true -and
    $boundary.publication_guard.removal_before_window_end_allowed -eq $false -and
    $boundary.publication_guard.silent_breaking_change_allowed -eq $false -and
    $boundary.publication_guard.publish_without_reviewed_policy_allowed -eq $false -and
    $boundary.publication_guard.unconfigured_behavior -eq "no-deprecation-scheduled" -and
    $boundary.publication_guard.window_elapsed_without_enforcement_ref -eq "hold-for-review") "DEPRECATION_PUBLICATION_GUARD_INVALID"
Assert-Condition ($boundary.runtime_boundary.consumes_published_snapshot -eq $true -and
    $boundary.runtime_boundary.control_plane_postgresql_query_allowed -eq $false -and
    $boundary.runtime_boundary.tenant_match_required -eq $true -and
    $boundary.runtime_boundary.config_version_match_required -eq $true -and
    $boundary.runtime_boundary.policy_revision_match_required -eq $true -and
    $boundary.runtime_boundary.resource_match_required -eq $true -and
    $boundary.runtime_boundary.evaluation_changes_resource_availability -eq $false) "DEPRECATION_RUNTIME_BOUNDARY_INVALID"
Assert-Condition ($boundary.notification.asynchronous_non_blocking -eq $true -and
    $boundary.notification.request_path_waits_for_delivery -eq $false -and
    $boundary.notification.usage_billing_audit_analytics_persistence_blocks_requests -eq $false) "DEPRECATION_NOTIFICATION_BLOCKS_REQUEST_PATH"
Assert-Condition ($boundary.configuration_lifecycle.versioned -eq $true -and
    $boundary.configuration_lifecycle.revision_required -eq $true -and
    $boundary.configuration_lifecycle.rollback_target_required -eq $true -and
    $boundary.configuration_lifecycle.prior_contract_retained_until_window_end -eq $true -and
    $boundary.configuration_lifecycle.last_valid_snapshot_preserved_on_publish_failure -eq $true) "DEPRECATION_ROLLBACK_GUARD_MISSING"
Assert-Condition (@($boundary.change_evidence.who_fields) -contains "updated_by" -and
    $boundary.change_evidence.revision_field -eq "revision" -and
    @($boundary.change_evidence.when_fields) -contains "window_starts_at" -and
    @($boundary.change_evidence.when_fields) -contains "window_ends_at" -and
    @($boundary.change_evidence.impact_scope_fields) -contains "resource_kind" -and
    @($boundary.change_evidence.impact_scope_fields) -contains "resource_ref" -and
    $boundary.change_evidence.rollback_revision_field -eq "rollback_revision") "DEPRECATION_CHANGE_EVIDENCE_MISSING"
foreach ($forbiddenLabel in @("evaluation_id", "resource_ref", "request_id", "trace_id", "user_id")) {
    Assert-Condition (@($boundary.telemetry.high_cardinality_labels_forbidden) -contains $forbiddenLabel) "DEPRECATION_HIGH_CARDINALITY_GUARD_MISSING"
}

$openApiPath = Join-Path $repoRoot "docs/contracts/openapi/openapi.yaml"
$openApi = Get-Content -LiteralPath $openApiPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ($openApi.'x-deprecation-contract' -eq "../deprecation/deprecation-boundary.v1.json") "OPENAPI_DEPRECATION_CONTRACT_MISSING"
Assert-Condition ([string]$openApi.'x-deprecation-window-tbd' -match "TBD-015") "OPENAPI_DEPRECATION_TBD_GUARD_MISSING"
$chatOperation = $openApi.paths.'/v1/chat/completions'.post
Assert-Condition ($null -eq $chatOperation.PSObject.Properties['deprecated']) "OPENAPI_OPERATION_PREMATURELY_DEPRECATED"

# All timestamps and references below are conformance fixtures, not production defaults or recommendations.
$fixturePolicy = [PSCustomObject]@{
    tenant_id = "tenant-fixture"
    config_version = 12
    revision = 4
    resource_kind = "api"
    resource_ref = "api://fixture/v1/example"
    replacement_ref = "api://fixture/v2/example"
    announcement_at = "2026-01-05T00:00:00Z"
    window_starts_at = "2026-01-10T00:00:00Z"
    window_ends_at = "2026-01-20T00:00:00Z"
    enforcement_after_window_ref = "enforcement://fixture/reviewed"
}
$fixtureContext = [PSCustomObject]@{
    tenant_id = "tenant-fixture"
    config_version = 12
    policy_revision = 4
    resource_kind = "api"
    resource_ref = "api://fixture/v1/example"
    evaluated_at = "2026-01-15T00:00:00Z"
}

foreach ($scenario in @(
    [PSCustomObject]@{ At = "2026-01-09T00:00:00Z"; State = "not_started"; Reason = "DEPRECATION_NOT_STARTED" },
    [PSCustomObject]@{ At = "2026-01-10T00:00:00Z"; State = "in_window"; Reason = "DEPRECATION_WINDOW_ACTIVE" },
    [PSCustomObject]@{ At = "2026-01-20T00:00:00Z"; State = "window_elapsed"; Reason = "DEPRECATION_WINDOW_ELAPSED" }
)) {
    $context = Copy-ContractObject $fixtureContext
    $context.evaluated_at = $scenario.At
    $evaluation = Invoke-ReferenceDeprecationEvaluation $fixturePolicy $context
    Assert-Condition ($evaluation.state -eq $scenario.State -and $evaluation.reason_code -eq $scenario.Reason) ("DEPRECATION_LIFECYCLE_SCENARIO_FAILED_" + $scenario.State)
}

$unconfiguredPolicy = Copy-ContractObject $fixturePolicy
$unconfiguredPolicy.window_starts_at = $null
$unconfiguredPolicy.window_ends_at = $null
$unconfiguredEvaluation = Invoke-ReferenceDeprecationEvaluation $unconfiguredPolicy $fixtureContext
Assert-Condition ($unconfiguredEvaluation.state -eq "unconfigured" -and $unconfiguredEvaluation.reason_code -eq "DEPRECATION_POLICY_UNCONFIGURED") "DEPRECATION_UNCONFIGURED_POLICY_ACTIVATED"
$invalidPolicy = Copy-ContractObject $fixturePolicy
$invalidPolicy.window_ends_at = "2026-01-09T00:00:00Z"
$invalidEvaluation = Invoke-ReferenceDeprecationEvaluation $invalidPolicy $fixtureContext
Assert-Condition ($invalidEvaluation.state -eq "invalid" -and $invalidEvaluation.reason_code -eq "DEPRECATION_WINDOW_INVALID") "DEPRECATION_INVALID_WINDOW_ACCEPTED"
$lateAnnouncementPolicy = Copy-ContractObject $fixturePolicy
$lateAnnouncementPolicy.announcement_at = "2026-01-11T00:00:00Z"
$lateAnnouncementEvaluation = Invoke-ReferenceDeprecationEvaluation $lateAnnouncementPolicy $fixtureContext
Assert-Condition ($lateAnnouncementEvaluation.state -eq "invalid" -and $lateAnnouncementEvaluation.reason_code -eq "DEPRECATION_WINDOW_INVALID") "DEPRECATION_LATE_ANNOUNCEMENT_ACCEPTED"

foreach ($scenario in @(
    [PSCustomObject]@{ Reason = "DEPRECATION_TENANT_MISMATCH"; Mutate = { param($c) $c.tenant_id = "tenant-other" } },
    [PSCustomObject]@{ Reason = "DEPRECATION_CONFIG_VERSION_MISMATCH"; Mutate = { param($c) $c.config_version = 13 } },
    [PSCustomObject]@{ Reason = "DEPRECATION_POLICY_REVISION_MISMATCH"; Mutate = { param($c) $c.policy_revision = 5 } },
    [PSCustomObject]@{ Reason = "DEPRECATION_RESOURCE_MISMATCH"; Mutate = { param($c) $c.resource_ref = "api://fixture/other" } }
)) {
    $context = Copy-ContractObject $fixtureContext
    & $scenario.Mutate $context
    $evaluation = Invoke-ReferenceDeprecationEvaluation $fixturePolicy $context
    Assert-Condition ($evaluation.state -eq "indeterminate" -and $evaluation.reason_code -eq $scenario.Reason) ("DEPRECATION_SCENARIO_FAILED_" + $scenario.Reason)
}

foreach ($resourceKind in @($baseline.required_resource_kinds)) {
    $policy = Copy-ContractObject $fixturePolicy
    $context = Copy-ContractObject $fixtureContext
    $policy.resource_kind = $resourceKind
    $policy.resource_ref = $resourceKind + "://fixture/resource"
    $context.resource_kind = $resourceKind
    $context.resource_ref = $policy.resource_ref
    $evaluation = Invoke-ReferenceDeprecationEvaluation $policy $context
    Assert-Condition ($evaluation.state -eq "in_window" -and $evaluation.reason_code -eq "DEPRECATION_WINDOW_ACTIVE") ("DEPRECATION_RESOURCE_KIND_EVALUATION_FAILED_" + $resourceKind)
}

$globalPolicy = Copy-ContractObject $fixturePolicy
$globalPolicy.tenant_id = $null
$globalEvaluation = Invoke-ReferenceDeprecationEvaluation $globalPolicy $fixtureContext
Assert-Condition ($globalEvaluation.state -eq "in_window") "DEPRECATION_GLOBAL_POLICY_REJECTED"

$serializedEvaluation = Invoke-ReferenceDeprecationEvaluation $fixturePolicy $fixtureContext | ConvertTo-Json -Depth 20 -Compress
foreach ($forbiddenField in @($baseline.forbidden_evaluation_fields)) {
    Assert-Condition (-not $serializedEvaluation.ToLowerInvariant().Contains(([string]$forbiddenField).ToLowerInvariant())) "DEPRECATION_EVALUATION_DISCLOSURE_FORBIDDEN"
}

Write-Output "status=pass reason_code=DEPRECATION_WINDOW_CONFIGURABILITY_OK tbd=TBD-015 duration=unconfigured enforcement=unconfigured notification=unconfigured"
