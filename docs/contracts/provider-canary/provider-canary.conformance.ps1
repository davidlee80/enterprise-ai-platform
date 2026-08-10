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
        throw "PROVIDER_CANARY_CONTRACT_FILE_MISSING: $path"
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

function New-CanaryDecision {
    param(
        [object]$Context,
        [string]$Outcome,
        [string]$ReasonCode,
        [object]$NextStageId,
        [object]$RollbackRevision
    )

    return [PSCustomObject][ordered]@{
        schema_version = 1
        decision_id = "decision-fixture"
        observation_id = [string]$Context.observation_id
        decided_at = "2026-01-01T00:00:00Z"
        tenant_id = [string]$Context.tenant_id
        config_version = [int]$Context.config_version
        policy_revision = [int]$Context.policy_revision
        stage_id = [string]$Context.stage_id
        model_alias = [string]$Context.model_alias
        provider_ids = @($Context.provider_ids)
        outcome = $Outcome
        reason_code = $ReasonCode
        next_stage_id = $NextStageId
        rollback_revision = $RollbackRevision
    }
}

function Invoke-ReferenceCanaryEvaluation {
    param(
        [object]$Policy,
        [object]$Observation,
        [AllowNull()][string]$CriteriaResult
    )

    if ($null -eq $Policy -or
        $null -eq $Policy.baseline_provider_ids -or
        $null -eq $Policy.canary_provider_ids -or
        $null -eq $Policy.stages -or
        [string]::IsNullOrWhiteSpace([string]$Policy.allocation_key_ref) -or
        [string]::IsNullOrWhiteSpace([string]$Policy.allocation_algorithm_ref) -or
        [string]::IsNullOrWhiteSpace([string]$Policy.signal_set_ref)) {
        return New-CanaryDecision $Observation "hold" "CANARY_POLICY_UNCONFIGURED" $null $null
    }
    if ([string]$Observation.tenant_id -ne [string]$Policy.tenant_id) {
        return New-CanaryDecision $Observation "indeterminate" "CANARY_TENANT_MISMATCH" $null $null
    }
    if ([int]$Observation.config_version -ne [int]$Policy.config_version) {
        return New-CanaryDecision $Observation "indeterminate" "CANARY_CONFIG_VERSION_MISMATCH" $null $null
    }
    if ([int]$Observation.policy_revision -ne [int]$Policy.revision) {
        return New-CanaryDecision $Observation "indeterminate" "CANARY_POLICY_REVISION_MISMATCH" $null $null
    }
    if ([string]$Observation.model_alias -ne [string]$Policy.model_alias) {
        return New-CanaryDecision $Observation "indeterminate" "CANARY_MODEL_ALIAS_MISMATCH" $null $null
    }

    $stages = @($Policy.stages)
    $configuredProviderIds = @($Policy.baseline_provider_ids) + @($Policy.canary_provider_ids)
    if (@($configuredProviderIds | Select-Object -Unique).Count -ne $configuredProviderIds.Count) {
        return New-CanaryDecision $Observation "indeterminate" "CANARY_STAGE_INVALID" $null $null
    }
    $stageIndex = -1
    for ($index = 0; $index -lt $stages.Count; $index++) {
        if ([string]$stages[$index].stage_id -eq [string]$Observation.stage_id) {
            $stageIndex = $index
            break
        }
    }
    if ($stageIndex -lt 0) {
        return New-CanaryDecision $Observation "indeterminate" "CANARY_STAGE_INVALID" $null $null
    }
    $stage = $stages[$stageIndex]
    $weightedProviderIds = @($stage.provider_weights.PSObject.Properties.Name)
    if (@($weightedProviderIds | Where-Object { $configuredProviderIds -notcontains $_ }).Count -gt 0) {
        return New-CanaryDecision $Observation "indeterminate" "CANARY_STAGE_INVALID" $null $null
    }
    if ($Observation.window_complete -ne $true) {
        return New-CanaryDecision $Observation "hold" "CANARY_OBSERVATION_WINDOW_INCOMPLETE" $null $null
    }
    if ([int]$Observation.sample_count -lt [int]$stage.minimum_sample_size) {
        return New-CanaryDecision $Observation "hold" "CANARY_SAMPLE_INSUFFICIENT" $null $null
    }
    if ($Observation.signals_available -ne $true) {
        return New-CanaryDecision $Observation "hold" "CANARY_SIGNAL_UNAVAILABLE" $null $null
    }
    if ([string]::IsNullOrWhiteSpace($CriteriaResult)) {
        return New-CanaryDecision $Observation "hold" "CANARY_CRITERIA_UNCONFIGURED" $null $null
    }

    switch ($CriteriaResult) {
        "promote" {
            if (($stageIndex + 1) -ge $stages.Count) {
                return New-CanaryDecision $Observation "hold" "CANARY_HOLD" $null $null
            }
            return New-CanaryDecision $Observation "promote" "CANARY_PROMOTE" ([string]$stages[$stageIndex + 1].stage_id) $null
        }
        "rollback" {
            return New-CanaryDecision $Observation "rollback" "CANARY_ROLLBACK" $null $Policy.rollback_revision
        }
        "hold" {
            return New-CanaryDecision $Observation "hold" "CANARY_HOLD" $null $null
        }
        default {
            return New-CanaryDecision $Observation "hold" "CANARY_CRITERIA_UNCONFIGURED" $null $null
        }
    }
}

function Get-CanaryEligibleProviderIds {
    param(
        [string[]]$HardFilteredCandidateIds,
        [object]$Policy
    )

    $policyProviderIds = @($Policy.baseline_provider_ids) + @($Policy.canary_provider_ids)
    return @($HardFilteredCandidateIds | Where-Object { $policyProviderIds -contains $_ })
}

$policySchema = Read-ContractJson "provider-canary-policy.v1.schema.json"
$observationSchema = Read-ContractJson "provider-canary-observation.v1.schema.json"
$decisionSchema = Read-ContractJson "provider-canary-decision.v1.schema.json"
$boundary = Read-ContractJson "provider-canary-boundary.v1.json"
$baseline = Read-ContractJson "provider-canary-compatibility-baseline.v1.json"

foreach ($schema in @($policySchema, $observationSchema, $decisionSchema)) {
    Assert-Condition ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "PROVIDER_CANARY_SCHEMA_DRAFT_INVALID"
    Assert-Condition ($schema.additionalProperties -eq $false) "PROVIDER_CANARY_SCHEMA_UNVERSIONED_EXTENSION_ALLOWED"
}
Assert-Condition ($policySchema.'$id' -eq $baseline.policy_schema_id) "PROVIDER_CANARY_POLICY_SCHEMA_ID_CHANGED"
Assert-Condition ($observationSchema.'$id' -eq $baseline.observation_schema_id) "PROVIDER_CANARY_OBSERVATION_SCHEMA_ID_CHANGED"
Assert-Condition ($decisionSchema.'$id' -eq $baseline.decision_schema_id) "PROVIDER_CANARY_DECISION_SCHEMA_ID_CHANGED"
foreach ($field in @($baseline.required_policy_fields)) {
    Assert-Condition (@($policySchema.required) -contains [string]$field) "PROVIDER_CANARY_POLICY_FIELD_REMOVED"
}
foreach ($field in @($baseline.required_observation_fields)) {
    Assert-Condition (@($observationSchema.required) -contains [string]$field) "PROVIDER_CANARY_OBSERVATION_FIELD_REMOVED"
}
foreach ($field in @($baseline.required_decision_fields)) {
    Assert-Condition (@($decisionSchema.required) -contains [string]$field) "PROVIDER_CANARY_DECISION_FIELD_REMOVED"
}
foreach ($outcome in @($baseline.required_outcomes)) {
    Assert-Condition (@($decisionSchema.properties.outcome.enum) -contains [string]$outcome) "PROVIDER_CANARY_DECISION_OUTCOME_REMOVED"
}
foreach ($reasonCode in @($baseline.required_reason_codes)) {
    Assert-Condition (@($decisionSchema.properties.reason_code.enum) -contains [string]$reasonCode) "PROVIDER_CANARY_REASON_CODE_REMOVED"
}
Assert-Condition ($policySchema.properties.decision_status.const -eq "TBD-014") "PROVIDER_CANARY_TBD_GUARD_MISSING"
foreach ($nullableField in @("baseline_provider_ids", "canary_provider_ids", "stages", "allocation_key_ref", "allocation_algorithm_ref", "signal_set_ref", "automatic_promotion_enabled", "automatic_rollback_enabled")) {
    Assert-Condition (@($policySchema.properties.$nullableField.type) -contains "null") "PROVIDER_CANARY_UNCONFIGURED_POLICY_NOT_SUPPORTED"
}
Assert-Condition ($policySchema.properties.stages.items.additionalProperties -eq $false) "PROVIDER_CANARY_STAGE_EXTENSION_UNVERSIONED"

Assert-Condition ($boundary.status -eq "canary-interface-ready-policy-unconfigured" -and $boundary.decision_status -eq "TBD-014") "PROVIDER_CANARY_BOUNDARY_STATUS_INVALID"
foreach ($field in @($baseline.required_unresolved_policy_fields)) {
    Assert-Condition ($null -eq $boundary.current_policy.$field) "PROVIDER_CANARY_PRODUCTION_VALUE_PREMATURELY_SELECTED"
}
Assert-Condition ($boundary.runtime_boundary.consumes_published_snapshot -eq $true -and
    $boundary.runtime_boundary.control_plane_postgresql_query_allowed -eq $false -and
    $boundary.runtime_boundary.tenant_match_required -eq $true -and
    $boundary.runtime_boundary.config_version_match_required -eq $true -and
    $boundary.runtime_boundary.policy_revision_match_required -eq $true -and
    $boundary.runtime_boundary.model_alias_match_required -eq $true) "PROVIDER_CANARY_CP_DP_OR_ISOLATION_GUARD_MISSING"
Assert-Condition ($boundary.runtime_boundary.hard_policy_filters_precede_weighting -eq $true -and
    $boundary.runtime_boundary.weight_overrides_region_or_compliance -eq $false -and
    $boundary.runtime_boundary.weight_is_priority -eq $false -and
    $boundary.runtime_boundary.selection_algorithm_selected -eq $false) "PROVIDER_CANARY_ROUTING_PRECEDENCE_INVALID"
Assert-Condition ($boundary.observation.asynchronous_non_blocking -eq $true -and
    $boundary.observation.request_path_waits_for_window -eq $false -and
    $boundary.observation.usage_billing_audit_analytics_persistence_blocks_routing -eq $false) "PROVIDER_CANARY_OBSERVATION_BLOCKS_REQUEST_PATH"
Assert-Condition ($boundary.progression.full_replacement_without_canary_allowed -eq $false -and
    $boundary.progression.unconfigured_behavior -eq "hold" -and
    $boundary.progression.publish_requires_explicit_reviewed_policy -eq $true) "PROVIDER_CANARY_CONTROLLED_RELEASE_GUARD_MISSING"
Assert-Condition ($boundary.configuration_lifecycle.versioned -eq $true -and
    $boundary.configuration_lifecycle.revision_required -eq $true -and
    $boundary.configuration_lifecycle.rollback_target_required -eq $true -and
    $boundary.configuration_lifecycle.last_valid_snapshot_preserved_on_publish_failure -eq $true) "PROVIDER_CANARY_ROLLBACK_GUARD_MISSING"
Assert-Condition (@($boundary.change_evidence.who_fields) -contains "updated_by" -and
    $boundary.change_evidence.revision_field -eq "revision" -and
    @($boundary.change_evidence.when_fields) -contains "effective_at" -and
    @($boundary.change_evidence.impact_scope_fields) -contains "tenant_id" -and
    @($boundary.change_evidence.impact_scope_fields) -contains "model_alias" -and
    $boundary.change_evidence.rollback_revision_field -eq "rollback_revision") "PROVIDER_CANARY_CHANGE_EVIDENCE_MISSING"
foreach ($forbiddenLabel in @("request_id", "trace_id", "user_id", "prompt", "response_body")) {
    Assert-Condition (@($boundary.observation.high_cardinality_labels_forbidden) -contains $forbiddenLabel) "PROVIDER_CANARY_HIGH_CARDINALITY_GUARD_MISSING"
}

$routerBoundaryPath = Join-Path $repoRoot "docs/contracts/router/router-boundary.v1.json"
$routerBoundary = Get-Content -LiteralPath $routerBoundaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ($routerBoundary.weight_and_observation_contract -eq "docs/contracts/provider-canary/provider-canary-boundary.v1.json") "ROUTER_PROVIDER_CANARY_CONTRACT_MISSING"
Assert-Condition ($null -eq $routerBoundary.weight_and_observation_semantics -and $routerBoundary.weight_and_observation_status -eq "TBD-014") "ROUTER_PROVIDER_CANARY_SEMANTICS_PREMATURELY_SELECTED"

# Every value below is a conformance fixture, not a production default or recommendation.
$fixturePolicy = [PSCustomObject]@{
    tenant_id = "tenant-fixture"
    config_version = 9
    revision = 8
    rollback_revision = 7
    model_alias = "model-fixture"
    baseline_provider_ids = @("provider-baseline-fixture")
    canary_provider_ids = @("provider-canary-fixture")
    allocation_key_ref = "allocation-key://fixture"
    allocation_algorithm_ref = "allocation-algorithm://fixture"
    signal_set_ref = "signal-set://fixture"
    stages = @(
        [PSCustomObject]@{ stage_id = "stage-fixture-a"; provider_weights = [PSCustomObject]@{ 'provider-baseline-fixture' = 3; 'provider-canary-fixture' = 1 }; observation_window = "window-fixture-a"; minimum_sample_size = 2; promotion_criteria_ref = "criteria://fixture/promote-a"; rollback_criteria_ref = "criteria://fixture/rollback-a" },
        [PSCustomObject]@{ stage_id = "stage-fixture-b"; provider_weights = [PSCustomObject]@{ 'provider-baseline-fixture' = 1; 'provider-canary-fixture' = 3 }; observation_window = "window-fixture-b"; minimum_sample_size = 2; promotion_criteria_ref = "criteria://fixture/promote-b"; rollback_criteria_ref = "criteria://fixture/rollback-b" }
    )
}
$fixtureObservation = [PSCustomObject]@{
    observation_id = "observation-fixture"
    tenant_id = "tenant-fixture"
    config_version = 9
    policy_revision = 8
    stage_id = "stage-fixture-a"
    model_alias = "model-fixture"
    provider_ids = @("provider-baseline-fixture", "provider-canary-fixture")
    window_complete = $true
    sample_count = 2
    signals_available = $true
}

$promoteDecision = Invoke-ReferenceCanaryEvaluation $fixturePolicy $fixtureObservation "promote"
Assert-Condition ($promoteDecision.outcome -eq "promote" -and $promoteDecision.reason_code -eq "CANARY_PROMOTE" -and $promoteDecision.next_stage_id -eq "stage-fixture-b") "PROVIDER_CANARY_PROMOTION_EVALUATION_FAILED"
$rollbackDecision = Invoke-ReferenceCanaryEvaluation $fixturePolicy $fixtureObservation "rollback"
Assert-Condition ($rollbackDecision.outcome -eq "rollback" -and $rollbackDecision.reason_code -eq "CANARY_ROLLBACK" -and $rollbackDecision.rollback_revision -eq 7) "PROVIDER_CANARY_ROLLBACK_EVALUATION_FAILED"
$holdDecision = Invoke-ReferenceCanaryEvaluation $fixturePolicy $fixtureObservation "hold"
Assert-Condition ($holdDecision.outcome -eq "hold" -and $holdDecision.reason_code -eq "CANARY_HOLD") "PROVIDER_CANARY_HOLD_EVALUATION_FAILED"
$unconfiguredDecision = Invoke-ReferenceCanaryEvaluation $null $fixtureObservation $null
Assert-Condition ($unconfiguredDecision.outcome -eq "hold" -and $unconfiguredDecision.reason_code -eq "CANARY_POLICY_UNCONFIGURED") "PROVIDER_CANARY_UNCONFIGURED_POLICY_NOT_HELD"

foreach ($scenario in @(
    [PSCustomObject]@{ Reason = "CANARY_TENANT_MISMATCH"; Mutate = { param($o) $o.tenant_id = "tenant-other" } },
    [PSCustomObject]@{ Reason = "CANARY_CONFIG_VERSION_MISMATCH"; Mutate = { param($o) $o.config_version = 10 } },
    [PSCustomObject]@{ Reason = "CANARY_POLICY_REVISION_MISMATCH"; Mutate = { param($o) $o.policy_revision = 9 } },
    [PSCustomObject]@{ Reason = "CANARY_MODEL_ALIAS_MISMATCH"; Mutate = { param($o) $o.model_alias = "model-other" } },
    [PSCustomObject]@{ Reason = "CANARY_STAGE_INVALID"; Mutate = { param($o) $o.stage_id = "stage-missing" } }
)) {
    $observation = Copy-ContractObject $fixtureObservation
    & $scenario.Mutate $observation
    $decision = Invoke-ReferenceCanaryEvaluation $fixturePolicy $observation "hold"
    Assert-Condition ($decision.outcome -eq "indeterminate" -and $decision.reason_code -eq $scenario.Reason) ("PROVIDER_CANARY_SCENARIO_FAILED_" + $scenario.Reason)
}

$incompleteObservation = Copy-ContractObject $fixtureObservation
$incompleteObservation.window_complete = $false
$incompleteDecision = Invoke-ReferenceCanaryEvaluation $fixturePolicy $incompleteObservation "promote"
Assert-Condition ($incompleteDecision.outcome -eq "hold" -and $incompleteDecision.reason_code -eq "CANARY_OBSERVATION_WINDOW_INCOMPLETE") "PROVIDER_CANARY_INCOMPLETE_WINDOW_PROMOTED"
$insufficientObservation = Copy-ContractObject $fixtureObservation
$insufficientObservation.sample_count = 1
$insufficientDecision = Invoke-ReferenceCanaryEvaluation $fixturePolicy $insufficientObservation "promote"
Assert-Condition ($insufficientDecision.outcome -eq "hold" -and $insufficientDecision.reason_code -eq "CANARY_SAMPLE_INSUFFICIENT") "PROVIDER_CANARY_INSUFFICIENT_SAMPLE_PROMOTED"
$missingSignalObservation = Copy-ContractObject $fixtureObservation
$missingSignalObservation.signals_available = $false
$missingSignalDecision = Invoke-ReferenceCanaryEvaluation $fixturePolicy $missingSignalObservation "promote"
Assert-Condition ($missingSignalDecision.outcome -eq "hold" -and $missingSignalDecision.reason_code -eq "CANARY_SIGNAL_UNAVAILABLE") "PROVIDER_CANARY_MISSING_SIGNAL_PROMOTED"
$missingCriteriaDecision = Invoke-ReferenceCanaryEvaluation $fixturePolicy $fixtureObservation $null
Assert-Condition ($missingCriteriaDecision.outcome -eq "hold" -and $missingCriteriaDecision.reason_code -eq "CANARY_CRITERIA_UNCONFIGURED") "PROVIDER_CANARY_MISSING_CRITERIA_PROMOTED"

$hardFilteredIds = @("provider-canary-fixture")
$eligibleIds = @(Get-CanaryEligibleProviderIds $hardFilteredIds $fixturePolicy)
Assert-Condition ($eligibleIds.Count -eq 1 -and $eligibleIds[0] -eq "provider-canary-fixture" -and $eligibleIds -notcontains "provider-baseline-fixture") "PROVIDER_CANARY_RESTORED_HARD_FILTERED_CANDIDATE"

$serializedDecisions = @($promoteDecision, $rollbackDecision, $holdDecision, $unconfiguredDecision) | ConvertTo-Json -Depth 20 -Compress
foreach ($forbiddenField in @($baseline.forbidden_decision_fields)) {
    Assert-Condition (-not $serializedDecisions.ToLowerInvariant().Contains(([string]$forbiddenField).ToLowerInvariant())) "PROVIDER_CANARY_DECISION_DISCLOSURE_FORBIDDEN"
}

Write-Output "status=pass reason_code=PROVIDER_CANARY_CONFIGURABILITY_OK tbd=TBD-014 weights=unconfigured observation_window=unconfigured thresholds=unconfigured allocation=unconfigured"
