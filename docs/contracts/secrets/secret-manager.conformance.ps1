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
        throw "SECRET_CONTRACT_FILE_MISSING: $path"
    }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
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

function Copy-ContractObject {
    param([object]$Value)

    return $Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json
}

function New-SecretDecision {
    param(
        [object]$Request,
        [string]$Outcome,
        [string]$ReasonCode,
        [string]$Delivery,
        [object]$ExpiresAt,
        [string]$AuditOutcome = "enqueued",
        [string]$AuditReasonCode = "SECRET_AUDIT_EVENT_ENQUEUED"
    )

    return [PSCustomObject][ordered]@{
        schema_version = 1
        request_id = [string]$Request.request_id
        trace_id = [string]$Request.trace_id
        tenant_id = [string]$Request.reference.tenant_id
        config_version = [int]$Request.reference.config_version
        binding_revision = [int]$Request.binding_revision
        outcome = $Outcome
        reason_code = $ReasonCode
        delivery = $Delivery
        audit_outcome = $AuditOutcome
        audit_reason_code = $AuditReasonCode
        expires_at = $ExpiresAt
    }
}

function Complete-SecretResolution {
    param(
        [object]$Request,
        [string]$Outcome,
        [string]$ReasonCode,
        [object]$CredentialRecord,
        [scriptblock]$AuditWriter,
        [scriptblock]$CredentialConsumer
    )

    $expiresAt = if ($null -eq $CredentialRecord) { $null } else { $CredentialRecord.expires_at }
    $decision = New-SecretDecision $Request $Outcome $ReasonCode "not-delivered" $expiresAt
    $auditEvent = [PSCustomObject][ordered]@{
        schema_version = 1
        request_id = $decision.request_id
        trace_id = $decision.trace_id
        tenant_id = $decision.tenant_id
        config_version = $decision.config_version
        binding_revision = $decision.binding_revision
        outcome = $decision.outcome
        reason_code = $decision.reason_code
    }

    try {
        $auditAccepted = & $AuditWriter $auditEvent
    }
    catch {
        $auditAccepted = $false
    }
    if ($auditAccepted -ne $true) {
        $decision.audit_outcome = "rejected"
        $decision.audit_reason_code = "SECRET_AUDIT_EVENT_REJECTED"
    }

    if ($Outcome -ne "resolved") {
        return $decision
    }

    try {
        & $CredentialConsumer ([string]$CredentialRecord.credential_material)
    }
    catch {
        return New-SecretDecision $Request "unavailable" "SECRET_DELIVERY_FAILED" "not-delivered" $null $decision.audit_outcome $decision.audit_reason_code
    }
    return New-SecretDecision $Request "resolved" "SECRET_RESOLVED" "delivered-in-process" $expiresAt $decision.audit_outcome $decision.audit_reason_code
}

function Invoke-ReferenceSecretResolution {
    param(
        [object]$Request,
        [object]$CredentialRecord,
        [bool]$ManagerAvailable,
        [scriptblock]$AuditWriter,
        [scriptblock]$CredentialConsumer
    )

    if ([string]::IsNullOrWhiteSpace([string]$Request.reference.secret_ref)) {
        return Complete-SecretResolution $Request "denied" "SECRET_REFERENCE_INVALID" $null $AuditWriter $CredentialConsumer
    }
    if (-not $ManagerAvailable) {
        return Complete-SecretResolution $Request "unavailable" "SECRET_MANAGER_UNAVAILABLE" $null $AuditWriter $CredentialConsumer
    }
    if ($null -eq $CredentialRecord) {
        return Complete-SecretResolution $Request "denied" "SECRET_NOT_FOUND" $null $AuditWriter $CredentialConsumer
    }
    if ([string]$Request.reference.tenant_id -ne [string]$CredentialRecord.tenant_id) {
        return Complete-SecretResolution $Request "denied" "SECRET_TENANT_MISMATCH" $null $AuditWriter $CredentialConsumer
    }
    if ([int]$Request.reference.config_version -ne [int]$CredentialRecord.config_version) {
        return Complete-SecretResolution $Request "denied" "SECRET_CONFIG_VERSION_MISMATCH" $null $AuditWriter $CredentialConsumer
    }
    if ($CredentialRecord.access_allowed -ne $true) {
        return Complete-SecretResolution $Request "denied" "SECRET_ACCESS_DENIED" $null $AuditWriter $CredentialConsumer
    }
    if ($CredentialRecord.break_glass_only -eq $true) {
        return Complete-SecretResolution $Request "denied" "SECRET_BREAK_GLASS_REQUIRED" $null $AuditWriter $CredentialConsumer
    }
    if ($CredentialRecord.rotation_state_valid -ne $true) {
        return Complete-SecretResolution $Request "denied" "SECRET_ROTATION_STATE_INVALID" $null $AuditWriter $CredentialConsumer
    }
    return Complete-SecretResolution $Request "resolved" "SECRET_RESOLVED" $CredentialRecord $AuditWriter $CredentialConsumer
}

$referenceSchema = Read-ContractJson "secret-reference.v1.schema.json"
$requestSchema = Read-ContractJson "secret-resolution-request.v1.schema.json"
$decisionSchema = Read-ContractJson "secret-resolution-decision.v1.schema.json"
$bindingSchema = Read-ContractJson "secret-manager-binding.v1.schema.json"
$boundary = Read-ContractJson "secret-manager-boundary.v1.json"
$baseline = Read-ContractJson "secret-manager-compatibility-baseline.v1.json"

foreach ($schema in @($referenceSchema, $requestSchema, $decisionSchema, $bindingSchema)) {
    Assert-Condition ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "SECRET_SCHEMA_DRAFT_INVALID"
    Assert-Condition ($schema.additionalProperties -eq $false) "SECRET_SCHEMA_UNVERSIONED_EXTENSION_ALLOWED"
}
foreach ($pair in @(
    [PSCustomObject]@{ Schema = $referenceSchema; Id = $baseline.reference_schema_id; Fields = @($baseline.required_reference_fields) },
    [PSCustomObject]@{ Schema = $requestSchema; Id = $baseline.request_schema_id; Fields = @($baseline.required_request_fields) },
    [PSCustomObject]@{ Schema = $decisionSchema; Id = $baseline.decision_schema_id; Fields = @($baseline.required_decision_fields) },
    [PSCustomObject]@{ Schema = $bindingSchema; Id = $baseline.binding_schema_id; Fields = @($baseline.required_binding_fields) }
)) {
    Assert-Condition ($pair.Schema.'$id' -eq $pair.Id) "SECRET_SCHEMA_ID_CHANGED"
    foreach ($field in $pair.Fields) {
        Assert-Condition (@($pair.Schema.required) -contains [string]$field) "SECRET_REQUIRED_FIELD_REMOVED"
    }
}

$secretRefProperty = $referenceSchema.properties.secret_ref
Assert-Condition ($secretRefProperty.writeOnly -eq $true) "SECRET_REFERENCE_NOT_WRITE_ONLY"
foreach ($formatConstraint in @("enum", "const", "pattern", "format")) {
    Assert-Condition (@($secretRefProperty.PSObject.Properties.Name) -notcontains $formatConstraint) "SECRET_REFERENCE_FORMAT_PREMATURELY_SELECTED"
}
Assert-Condition ($requestSchema.properties.reference.'$ref' -eq "secret-reference.v1.schema.json") "SECRET_REQUEST_REFERENCE_SCHEMA_MISSING"
foreach ($outcome in @($baseline.required_outcomes)) {
    Assert-Condition (@($decisionSchema.properties.outcome.enum) -contains [string]$outcome) "SECRET_DECISION_OUTCOME_REMOVED"
}
foreach ($reasonCode in @($baseline.required_reason_codes)) {
    Assert-Condition (@($decisionSchema.properties.reason_code.enum) -contains [string]$reasonCode) "SECRET_DECISION_REASON_REMOVED"
}
foreach ($auditOutcome in @($baseline.required_audit_outcomes)) {
    Assert-Condition (@($decisionSchema.properties.audit_outcome.enum) -contains [string]$auditOutcome) "SECRET_AUDIT_OUTCOME_REMOVED"
}
foreach ($auditReasonCode in @($baseline.required_audit_reason_codes)) {
    Assert-Condition (@($decisionSchema.properties.audit_reason_code.enum) -contains [string]$auditReasonCode) "SECRET_AUDIT_REASON_REMOVED"
}
$decisionProperties = @($decisionSchema.properties.PSObject.Properties.Name)
foreach ($forbiddenField in @($baseline.forbidden_decision_fields)) {
    Assert-Condition ($decisionProperties -notcontains [string]$forbiddenField) "SECRET_DECISION_SENSITIVE_FIELD_FOUND"
}

Assert-Condition ($bindingSchema.properties.decision_status.const -eq "TBD-012") "SECRET_MANAGER_TBD_GUARD_MISSING"
Assert-Condition (@($bindingSchema.properties.product_id.type) -contains "null") "SECRET_MANAGER_NULL_PRODUCT_NOT_SUPPORTED"
Assert-Condition (@($bindingSchema.properties.product_id.PSObject.Properties.Name) -notcontains "enum") "SECRET_MANAGER_PRODUCT_PREMATURELY_SELECTED"
Assert-Condition ($boundary.status -eq "reference-ready-product-unselected" -and $boundary.decision_status -eq "TBD-012") "SECRET_MANAGER_BOUNDARY_STATUS_INVALID"
foreach ($property in @($boundary.current_binding.PSObject.Properties)) {
    Assert-Condition ($null -eq $property.Value) "SECRET_MANAGER_BINDING_PREMATURELY_SELECTED"
}
Assert-Condition ($boundary.binding_registry.cardinality -eq "one-or-more-reviewed-bindings" -and
    $boundary.binding_registry.single_product_required -eq $false -and
    $boundary.binding_registry.tenant_scoped_selection_required -eq $true) "SECRET_MANAGER_REGISTRY_LOCK_IN_FOUND"
Assert-Condition ($boundary.resolution_interface.secret_ref_is_opaque -eq $true -and
    $boundary.resolution_interface.secret_ref_format_selected -eq $false -and
    $boundary.resolution_interface.tenant_checked_before_resolution -eq $true -and
    $boundary.resolution_interface.config_version_checked_before_resolution -eq $true -and
    $boundary.resolution_interface.asynchronous_audit_event_required -eq $true -and
    $boundary.resolution_interface.audit_persistence_blocks_delivery -eq $false -and
    $boundary.resolution_interface.credential_delivery -eq "in-process-non-serializable") "SECRET_RESOLUTION_INTERFACE_GUARD_INVALID"
foreach ($materialGuard in @("credential_persistence_allowed", "credential_logging_allowed", "credential_telemetry_allowed", "credential_error_disclosure_allowed")) {
    Assert-Condition ($boundary.resolution_interface.$materialGuard -eq $false) "SECRET_MATERIAL_DISCLOSURE_GUARD_MISSING"
}
Assert-Condition ($boundary.rotation.policy_ref_required_before_activation -eq $true -and
    $null -eq $boundary.rotation.schedule -and
    $null -eq $boundary.rotation.overlap_behavior -and
    $null -eq $boundary.rotation.revocation_behavior) "SECRET_ROTATION_POLICY_PREMATURELY_SELECTED"
Assert-Condition ($boundary.break_glass.separate_controlled_workflow_required -eq $true -and
    $boundary.break_glass.normal_resolver_bypass_allowed -eq $false -and
    $null -eq $boundary.break_glass.workflow_ref -and
    $null -eq $boundary.break_glass.approval_system_ref) "SECRET_BREAK_GLASS_BOUNDARY_INVALID"
Assert-Condition ($boundary.configuration_lifecycle.versioned -eq $true -and
    $boundary.configuration_lifecycle.rollback_required -eq $true) "SECRET_MANAGER_ROLLBACK_GUARD_MISSING"
Assert-Condition ($boundary.runtime_boundary.product_sdk_behind_adapter -eq $true -and
    $boundary.runtime_boundary.published_binding_required -eq $true -and
    $boundary.runtime_boundary.control_plane_postgresql_query_allowed -eq $false -and
    $boundary.runtime_boundary.audit_persistence_is_async_side_effect -eq $true) "SECRET_RUNTIME_OR_ASYNC_AUDIT_BOUNDARY_INVALID"

$providerBoundaryPath = Join-Path $repoRoot "docs/contracts/providers/provider-adapter-boundary.v1.json"
$providerBoundary = Get-Content -LiteralPath $providerBoundaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ($providerBoundary.secret_resolver_contract -eq "docs/contracts/secrets/secret-manager-boundary.v1.json") "PROVIDER_SECRET_RESOLVER_CONTRACT_MISSING"
Assert-Condition ($null -eq $providerBoundary.secret_resolver -and $providerBoundary.secret_resolver_status -eq "TBD-012") "PROVIDER_SECRET_MANAGER_PREMATURELY_SELECTED"

$operationsBoundaryPath = Join-Path $repoRoot "ops/coordination/operations-coordination-boundary.v1.json"
Assert-Condition ($boundary.approval_contract -eq "ops/coordination/operations-coordination-boundary.v1.json") "SECRET_APPROVAL_CONTRACT_MISSING"
Assert-Condition (Test-Path -LiteralPath $operationsBoundaryPath -PathType Leaf) "SECRET_APPROVAL_CONTRACT_FILE_MISSING"

$secretReferenceValue = "opaque-secret-reference-test-only"
$credentialValue = "ephemeral-credential-" + [Guid]::NewGuid().ToString("N")
$baseRequest = [PSCustomObject]@{
    schema_version = 1
    request_id = "request-secret-test"
    trace_id = "trace-secret-test"
    binding_revision = 7
    reference = [PSCustomObject]@{
        schema_version = 1
        tenant_id = "tenant-a"
        config_version = 42
        purpose = "provider-credential-test"
        secret_ref = $secretReferenceValue
    }
}
$baseRecord = [PSCustomObject]@{
    tenant_id = "tenant-a"
    config_version = 42
    access_allowed = $true
    break_glass_only = $false
    rotation_state_valid = $true
    credential_material = $credentialValue
    expires_at = $null
}
$script:auditEvents = @()
$auditWriter = {
    param($event)
    $script:auditEvents += Copy-ContractObject $event
    return $true
}
$failedAuditWriter = { param($event) return $false }
$script:deliveredValues = @()
$credentialConsumer = {
    param($value)
    $script:deliveredValues += $value
}
$failedCredentialConsumer = { param($value) throw "test delivery failure" }

$successDecision = Invoke-ReferenceSecretResolution (Copy-ContractObject $baseRequest) (Copy-ContractObject $baseRecord) $true $auditWriter $credentialConsumer
Assert-Condition ($successDecision.outcome -eq "resolved" -and $successDecision.reason_code -eq "SECRET_RESOLVED" -and $successDecision.delivery -eq "delivered-in-process") "SECRET_NORMAL_RESOLUTION_FAILED"
Assert-Condition ($script:deliveredValues.Count -eq 1 -and $script:deliveredValues[0] -eq $credentialValue) "SECRET_CREDENTIAL_NOT_DELIVERED_IN_PROCESS"

$scenarioDecisions = @()
foreach ($scenario in @(
    [PSCustomObject]@{ Reason = "SECRET_REFERENCE_INVALID"; Delivery = "not-delivered"; AuditOutcome = "enqueued"; DeliveryDelta = 0; Manager = $true; Record = (Copy-ContractObject $baseRecord); Mutate = { param($request, $record) $request.reference.secret_ref = "" }; Audit = $auditWriter; Consumer = $credentialConsumer },
    [PSCustomObject]@{ Reason = "SECRET_NOT_FOUND"; Delivery = "not-delivered"; AuditOutcome = "enqueued"; DeliveryDelta = 0; Manager = $true; Record = $null; Mutate = { param($request, $record) }; Audit = $auditWriter; Consumer = $credentialConsumer },
    [PSCustomObject]@{ Reason = "SECRET_TENANT_MISMATCH"; Delivery = "not-delivered"; AuditOutcome = "enqueued"; DeliveryDelta = 0; Manager = $true; Record = (Copy-ContractObject $baseRecord); Mutate = { param($request, $record) $record.tenant_id = "tenant-b" }; Audit = $auditWriter; Consumer = $credentialConsumer },
    [PSCustomObject]@{ Reason = "SECRET_CONFIG_VERSION_MISMATCH"; Delivery = "not-delivered"; AuditOutcome = "enqueued"; DeliveryDelta = 0; Manager = $true; Record = (Copy-ContractObject $baseRecord); Mutate = { param($request, $record) $record.config_version = 41 }; Audit = $auditWriter; Consumer = $credentialConsumer },
    [PSCustomObject]@{ Reason = "SECRET_ACCESS_DENIED"; Delivery = "not-delivered"; AuditOutcome = "enqueued"; DeliveryDelta = 0; Manager = $true; Record = (Copy-ContractObject $baseRecord); Mutate = { param($request, $record) $record.access_allowed = $false }; Audit = $auditWriter; Consumer = $credentialConsumer },
    [PSCustomObject]@{ Reason = "SECRET_MANAGER_UNAVAILABLE"; Delivery = "not-delivered"; AuditOutcome = "enqueued"; DeliveryDelta = 0; Manager = $false; Record = (Copy-ContractObject $baseRecord); Mutate = { param($request, $record) }; Audit = $auditWriter; Consumer = $credentialConsumer },
    [PSCustomObject]@{ Reason = "SECRET_ROTATION_STATE_INVALID"; Delivery = "not-delivered"; AuditOutcome = "enqueued"; DeliveryDelta = 0; Manager = $true; Record = (Copy-ContractObject $baseRecord); Mutate = { param($request, $record) $record.rotation_state_valid = $false }; Audit = $auditWriter; Consumer = $credentialConsumer },
    [PSCustomObject]@{ Reason = "SECRET_BREAK_GLASS_REQUIRED"; Delivery = "not-delivered"; AuditOutcome = "enqueued"; DeliveryDelta = 0; Manager = $true; Record = (Copy-ContractObject $baseRecord); Mutate = { param($request, $record) $record.break_glass_only = $true }; Audit = $auditWriter; Consumer = $credentialConsumer },
    [PSCustomObject]@{ Reason = "SECRET_RESOLVED"; Delivery = "delivered-in-process"; AuditOutcome = "rejected"; DeliveryDelta = 1; Manager = $true; Record = (Copy-ContractObject $baseRecord); Mutate = { param($request, $record) }; Audit = $failedAuditWriter; Consumer = $credentialConsumer },
    [PSCustomObject]@{ Reason = "SECRET_DELIVERY_FAILED"; Delivery = "not-delivered"; AuditOutcome = "enqueued"; DeliveryDelta = 0; Manager = $true; Record = (Copy-ContractObject $baseRecord); Mutate = { param($request, $record) }; Audit = $auditWriter; Consumer = $failedCredentialConsumer }
)) {
    $request = Copy-ContractObject $baseRequest
    $record = $scenario.Record
    & $scenario.Mutate $request $record
    $deliveryCountBefore = $script:deliveredValues.Count
    $decision = Invoke-ReferenceSecretResolution $request $record $scenario.Manager $scenario.Audit $scenario.Consumer
    Assert-Condition ($decision.reason_code -eq $scenario.Reason -and
        $decision.delivery -eq $scenario.Delivery -and
        $decision.audit_outcome -eq $scenario.AuditOutcome) ("SECRET_SCENARIO_FAILED_" + $scenario.Reason)
    Assert-Condition ($script:deliveredValues.Count -eq ($deliveryCountBefore + $scenario.DeliveryDelta)) ("SECRET_SCENARIO_DELIVERY_COUNT_INVALID_" + $scenario.Reason)
    $scenarioDecisions += $decision
}

$serializedSafeOutputs = @($successDecision, $scenarioDecisions, $script:auditEvents) | ConvertTo-Json -Depth 20 -Compress
foreach ($forbiddenValue in @($secretReferenceValue, $credentialValue, "credential_material", "secret_ref", "raw_error", "stack_trace")) {
    Assert-Condition (-not $serializedSafeOutputs.Contains($forbiddenValue)) "SECRET_SAFE_OUTPUT_DISCLOSURE_FOUND"
}

Write-Output "status=pass reason_code=SECRET_MANAGER_ABSTRACTION_OK tbd=TBD-012 product=unselected reference_format=unselected rotation_schedule=unselected"
