[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$contractRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $contractRoot)

function Read-ContractJson {
    param([string]$Name)

    $path = Join-Path $contractRoot $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "OPERATIONS_COORDINATION_FILE_MISSING: $path"
    }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Assert-Condition {
    param([bool]$Condition, [string]$ReasonCode)

    if (-not $Condition) {
        throw $ReasonCode
    }
}

function Test-OnCallReadiness {
    param([object]$Binding)

    foreach ($field in @("provider_adapter_ref", "schedule_ref", "escalation_policy_ref", "contact_target_ref")) {
        if ([string]::IsNullOrWhiteSpace([string]$Binding.$field)) {
            return "UNCONFIGURED"
        }
    }
    return "READY"
}

function Test-ApprovalReadiness {
    param([object]$Binding, [object]$Decision)

    if ([string]::IsNullOrWhiteSpace([string]$Binding.approval_system_ref) -or
        $null -eq $Binding.required_approver_count) {
        return "APPROVAL_SYSTEM_UNCONFIGURED"
    }
    if ($null -eq $Decision -or $Decision.outcome -eq "pending") {
        return "APPROVAL_PENDING"
    }
    if ($Decision.outcome -eq "indeterminate") {
        return "APPROVAL_SYSTEM_UNAVAILABLE"
    }
    if ($Decision.outcome -eq "rejected") {
        return "APPROVAL_REJECTED"
    }
    if ($Decision.outcome -ne "approved" -or
        $Decision.approval_system_ref -ne $Binding.approval_system_ref) {
        return "APPROVAL_AUTHORITY_INVALID"
    }
    if ($null -eq $Decision.decided_by_refs -or
        @($Decision.decided_by_refs).Count -lt [int]$Binding.required_approver_count -or
        [string]::IsNullOrWhiteSpace([string]$Decision.decided_at) -or
        [string]::IsNullOrWhiteSpace([string]$Decision.evidence_ref)) {
        return "APPROVAL_EVIDENCE_INCOMPLETE"
    }
    return "APPROVAL_GRANTED"
}

$onCallSchema = Read-ContractJson "on-call-binding.v1.schema.json"
$requestSchema = Read-ContractJson "approval-request.v1.schema.json"
$decisionSchema = Read-ContractJson "approval-decision.v1.schema.json"
$evidencePackSchema = Read-ContractJson "go-live-evidence-pack.v1.schema.json"
$boundary = Read-ContractJson "operations-coordination-boundary.v1.json"
$baseline = Read-ContractJson "operations-coordination-compatibility-baseline.v1.json"

foreach ($schema in @($onCallSchema, $requestSchema, $decisionSchema, $evidencePackSchema)) {
    Assert-Condition ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "OPERATIONS_COORDINATION_SCHEMA_DRAFT_INVALID"
    Assert-Condition ($schema.additionalProperties -eq $false) "OPERATIONS_COORDINATION_SCHEMA_EXTENSION_ALLOWED"
}
foreach ($pair in @(
    [PSCustomObject]@{ Schema = $onCallSchema; Id = $baseline.on_call_schema_id; Fields = @($baseline.required_on_call_fields) },
    [PSCustomObject]@{ Schema = $requestSchema; Id = $baseline.approval_request_schema_id; Fields = @($baseline.required_approval_request_fields) },
    [PSCustomObject]@{ Schema = $decisionSchema; Id = $baseline.approval_decision_schema_id; Fields = @($baseline.required_approval_decision_fields) },
    [PSCustomObject]@{ Schema = $evidencePackSchema; Id = $baseline.evidence_pack_schema_id; Fields = @($baseline.required_evidence_pack_fields) }
)) {
    Assert-Condition ($pair.Schema.'$id' -eq $pair.Id) "OPERATIONS_COORDINATION_SCHEMA_ID_CHANGED"
    foreach ($field in $pair.Fields) {
        Assert-Condition (@($pair.Schema.required) -contains [string]$field) "OPERATIONS_COORDINATION_REQUIRED_FIELD_REMOVED"
    }
}

Assert-Condition ($onCallSchema.properties.decision_status.const -eq "TBD-020") "ON_CALL_TBD_GUARD_MISSING"
foreach ($field in @($baseline.unresolved_on_call_fields)) {
    Assert-Condition (@($onCallSchema.properties.$field.type) -contains "null") "ON_CALL_NULL_PLACEHOLDER_NOT_SUPPORTED"
    Assert-Condition ($null -eq $boundary.current_on_call_binding.$field) "ON_CALL_SYSTEM_PREMATURELY_SELECTED"
}
foreach ($field in @($baseline.unresolved_approval_fields)) {
    Assert-Condition ($null -eq $boundary.current_approval_binding.$field) "APPROVAL_SYSTEM_PREMATURELY_SELECTED"
}

$schemaGateChecks = @($requestSchema.properties.required_gate_checks.items.enum)
$boundaryGateChecks = @($boundary.go_live_gate.required_checks)
foreach ($check in @($baseline.required_gate_checks)) {
    Assert-Condition ($schemaGateChecks -contains [string]$check) "GO_LIVE_SCHEMA_CHECK_REMOVED"
    Assert-Condition ($boundaryGateChecks -contains [string]$check) "GO_LIVE_BOUNDARY_CHECK_REMOVED"
}
Assert-Condition ($schemaGateChecks.Count -eq 7 -and $boundaryGateChecks.Count -eq 7) "GO_LIVE_GATE_CHECK_SET_CHANGED"
Assert-Condition ($boundary.go_live_gate.security_approval_required -eq $true -and
    $boundary.go_live_gate.evidence_pack_required -eq $true -and
    $boundary.go_live_gate.unconfigured_approval_system_blocks_promotion -eq $true -and
    $boundary.go_live_gate.unavailable_approval_system_blocks_promotion -eq $true -and
    $boundary.go_live_gate.implicit_self_approval_allowed -eq $false) "GO_LIVE_APPROVAL_GUARD_INVALID"
Assert-Condition ($boundary.runtime_boundary.online_data_plane_dependency_allowed -eq $false -and
    $boundary.runtime_boundary.approval_lookup_on_request_path_allowed -eq $false -and
    $boundary.runtime_boundary.on_call_lookup_on_request_path_allowed -eq $false -and
    $boundary.runtime_boundary.control_plane_postgresql_query_from_data_plane_allowed -eq $false) "OPERATIONS_COORDINATION_DATA_PLANE_COUPLING_FOUND"
Assert-Condition ($boundary.audit_safety.structured_decisions_required -eq $true -and
    $boundary.audit_safety.decision_evidence_required -eq $true -and
    $boundary.audit_safety.direct_contact_details_allowed -eq $false -and
    $boundary.audit_safety.credentials_allowed -eq $false -and
    $boundary.audit_safety.free_form_evidence_allowed -eq $false -and
    $boundary.audit_safety.audit_persistence_blocks_online_requests -eq $false) "OPERATIONS_COORDINATION_AUDIT_GUARD_INVALID"
Assert-Condition ($boundary.configuration_lifecycle.versioned -eq $true -and
    $boundary.configuration_lifecycle.revision_required -eq $true -and
    $boundary.configuration_lifecycle.rollback_required -eq $true -and
    $boundary.configuration_lifecycle.prior_compatible_revision_retained -eq $true) "OPERATIONS_COORDINATION_ROLLBACK_GUARD_MISSING"
Assert-Condition ($boundary.status -eq "interfaces-ready-systems-unconfigured" -and
    $boundary.decision_status -eq "TBD-020") "OPERATIONS_COORDINATION_STATUS_INVALID"

$schemaArtifacts = @($onCallSchema, $requestSchema, $decisionSchema, $evidencePackSchema) | ConvertTo-Json -Depth 30 -Compress
foreach ($field in @($baseline.forbidden_artifact_fields)) {
    Assert-Condition (-not $schemaArtifacts.Contains(('"' + [string]$field + '"'))) "OPERATIONS_COORDINATION_SENSITIVE_FIELD_FOUND"
}

Assert-Condition ((Test-OnCallReadiness $boundary.current_on_call_binding) -eq "UNCONFIGURED") "ON_CALL_UNCONFIGURED_STATE_INVALID"
Assert-Condition ((Test-ApprovalReadiness $boundary.current_approval_binding $null) -eq "APPROVAL_SYSTEM_UNCONFIGURED") "APPROVAL_UNCONFIGURED_STATE_INVALID"

$configuredOnCallFixture = [PSCustomObject]@{
    provider_adapter_ref = "adapter-ref-test-only"
    schedule_ref = "schedule-ref-test-only"
    escalation_policy_ref = "escalation-ref-test-only"
    contact_target_ref = "contact-target-ref-test-only"
}
Assert-Condition ((Test-OnCallReadiness $configuredOnCallFixture) -eq "READY") "ON_CALL_REFERENCE_INTERFACE_FAILED"

$configuredApprovalFixture = [PSCustomObject]@{
    approval_system_ref = "approval-system-ref-test-only"
    required_approver_count = 2
}
$approvedDecisionFixture = [PSCustomObject]@{
    outcome = "approved"
    approval_system_ref = "approval-system-ref-test-only"
    decided_by_refs = @("actor-ref-test-only-a", "actor-ref-test-only-b")
    decided_at = "2030-01-01T00:00:00Z"
    evidence_ref = "evidence-ref-test-only"
}
Assert-Condition ((Test-ApprovalReadiness $configuredApprovalFixture $approvedDecisionFixture) -eq "APPROVAL_GRANTED") "APPROVAL_REFERENCE_INTERFACE_FAILED"
$incompleteDecisionFixture = $approvedDecisionFixture | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$incompleteDecisionFixture.evidence_ref = $null
Assert-Condition ((Test-ApprovalReadiness $configuredApprovalFixture $incompleteDecisionFixture) -eq "APPROVAL_EVIDENCE_INCOMPLETE") "APPROVAL_EVIDENCE_FAIL_CLOSED_INVALID"
$unavailableDecisionFixture = [PSCustomObject]@{ outcome = "indeterminate" }
Assert-Condition ((Test-ApprovalReadiness $configuredApprovalFixture $unavailableDecisionFixture) -eq "APPROVAL_SYSTEM_UNAVAILABLE") "APPROVAL_UNAVAILABLE_FAIL_CLOSED_INVALID"

$runbookPath = Join-Path $repoRoot "ops/runbooks/README.md"
$runbookText = (Get-Content -LiteralPath $runbookPath -Raw -Encoding UTF8).ToLowerInvariant()
foreach ($term in @("symptom", "alert", "impact", "diagnosis", "mitigation", "rollback/failover", "verification", "escalation")) {
    Assert-Condition ($runbookText.Contains($term)) "RUNBOOK_REQUIRED_SECTION_MISSING"
}

Write-Output "status=pass reason_code=OPERATIONS_COORDINATION_INTERFACES_OK tbd=TBD-020 on_call_system=unconfigured approval_system=unconfigured approver_roles=unconfigured"
