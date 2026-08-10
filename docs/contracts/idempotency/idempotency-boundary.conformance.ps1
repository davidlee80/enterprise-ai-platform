[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$contractRoot = $PSScriptRoot
$requestSchemaPath = Join-Path $contractRoot "idempotency-request.v1.schema.json"
$decisionSchemaPath = Join-Path $contractRoot "idempotency-decision.v1.schema.json"
$policySchemaPath = Join-Path $contractRoot "idempotency-policy.v1.schema.json"
$boundaryPath = Join-Path $contractRoot "idempotency-boundary.v1.json"
$baselinePath = Join-Path $contractRoot "idempotency-compatibility-baseline.v1.json"

function Read-ContractJson {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "IDEMPOTENCY_CONTRACT_FILE_MISSING: $Path"
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

function Assert-RequiredFields {
    param(
        [object]$Schema,
        [object]$BaselineFields,
        [string]$ReasonCode
    )

    $required = @($Schema.required)
    foreach ($field in @($BaselineFields)) {
        Assert-Condition ($required -contains [string]$field) ($ReasonCode + "_" + ([string]$field).ToUpperInvariant())
    }
}

function Copy-ContractObject {
    param([object]$Value)

    return $Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json
}

function Invoke-ReferenceIdempotencyBoundary {
    param(
        [object]$Request,
        [hashtable]$Records
    )

    $tenantScope = if ($null -eq $Request.tenant_id) { "<authorized-global>" } else { [string]$Request.tenant_id }
    $lookupKey = $tenantScope + "|" + [string]$Request.operation_id + "|" + [string]$Request.idempotency_key
    $outcome = "proceed"
    $reasonCode = "IDEMPOTENCY_PROCEED"
    $recordVersion = 1

    if ($Records.ContainsKey($lookupKey)) {
        $record = $Records[$lookupKey]
        $recordVersion = [int]$record.record_version
        if ([string]$record.request_fingerprint -eq [string]$Request.request_fingerprint) {
            $outcome = "duplicate"
            $reasonCode = "IDEMPOTENCY_DUPLICATE"
        }
        else {
            $outcome = "conflict"
            $reasonCode = "IDEMPOTENCY_KEY_FINGERPRINT_CONFLICT"
        }
    }
    else {
        $Records[$lookupKey] = [PSCustomObject]@{
            request_fingerprint = [string]$Request.request_fingerprint
            record_version = 1
        }
    }

    return [PSCustomObject][ordered]@{
        schema_version = 1
        request_id = [string]$Request.request_id
        trace_id = [string]$Request.trace_id
        tenant_id = $Request.tenant_id
        operation_id = [string]$Request.operation_id
        config_version = [int]$Request.config_version
        outcome = $outcome
        reason_code = $reasonCode
        record_version = $recordVersion
        audit_required = $true
    }
}

$requestSchema = Read-ContractJson $requestSchemaPath
$decisionSchema = Read-ContractJson $decisionSchemaPath
$policySchema = Read-ContractJson $policySchemaPath
$boundary = Read-ContractJson $boundaryPath
$baseline = Read-ContractJson $baselinePath

foreach ($schema in @($requestSchema, $decisionSchema, $policySchema)) {
    Assert-Condition ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "IDEMPOTENCY_SCHEMA_DRAFT_INVALID"
    Assert-Condition ($schema.additionalProperties -eq $false) "IDEMPOTENCY_UNVERSIONED_EXTENSION_ALLOWED"
}

Assert-Condition ($requestSchema.'$id' -eq $baseline.request_schema_id) "IDEMPOTENCY_REQUEST_SCHEMA_ID_CHANGED"
Assert-Condition ($decisionSchema.'$id' -eq $baseline.decision_schema_id) "IDEMPOTENCY_DECISION_SCHEMA_ID_CHANGED"
Assert-Condition ($policySchema.'$id' -eq $baseline.policy_schema_id) "IDEMPOTENCY_POLICY_SCHEMA_ID_CHANGED"
Assert-RequiredFields $requestSchema $baseline.required_request_fields "IDEMPOTENCY_REQUEST_FIELD_REMOVED"
Assert-RequiredFields $decisionSchema $baseline.required_decision_fields "IDEMPOTENCY_DECISION_FIELD_REMOVED"
foreach ($outcome in @($baseline.required_outcomes)) {
    Assert-Condition (@($decisionSchema.properties.outcome.enum) -contains [string]$outcome) ("IDEMPOTENCY_OUTCOME_REMOVED_" + ([string]$outcome).ToUpperInvariant())
}

Assert-Condition ($boundary.status -eq "contract-extension-point") "IDEMPOTENCY_BOUNDARY_STATUS_INVALID"
Assert-Condition (@($boundary.requirements) -contains "TBD-005") "IDEMPOTENCY_TBD_TRACE_MISSING"
foreach ($pattern in @(
    "POST /admin/<resource>",
    "PATCH /admin/<resource>/{id}",
    "POST /admin/<resource>/{id}:publish",
    "POST /admin/<resource>/{id}:rollback"
)) {
    Assert-Condition (@($boundary.required_write_patterns) -contains $pattern) "IDEMPOTENCY_ADMIN_WRITE_PATTERN_MISSING"
}
Assert-Condition ($boundary.transport.status -eq "TBD-005" -and $null -eq $boundary.transport.header_name) "IDEMPOTENCY_HEADER_PREMATURELY_SELECTED"
Assert-Condition ($boundary.retention.status -eq "TBD-005" -and $null -eq $boundary.retention.ttl_seconds) "IDEMPOTENCY_TTL_PREMATURELY_SELECTED"
Assert-Condition ($boundary.storage.status -eq "TBD-005" -and $null -eq $boundary.storage.profile_ref) "IDEMPOTENCY_STORAGE_PREMATURELY_SELECTED"
Assert-Condition ($boundary.duplicate_handling.status -eq "TBD-005" -and $null -eq $boundary.duplicate_handling.response_strategy) "IDEMPOTENCY_REPLAY_PREMATURELY_SELECTED"
Assert-Condition ($boundary.conflict_handling.status -eq "TBD-005" -and $null -eq $boundary.conflict_handling.response_strategy) "IDEMPOTENCY_CONFLICT_PREMATURELY_SELECTED"
Assert-Condition ($boundary.store_failure_handling.status -eq "TBD-005" -and $null -eq $boundary.store_failure_handling.strategy) "IDEMPOTENCY_FAILURE_PREMATURELY_SELECTED"
Assert-Condition (@($boundary.isolation.minimum_dimensions) -contains "resolved_tenant_scope") "IDEMPOTENCY_TENANT_SCOPE_MISSING"
Assert-Condition (@($boundary.isolation.minimum_dimensions) -contains "idempotency_key") "IDEMPOTENCY_KEY_SCOPE_MISSING"
Assert-Condition ($boundary.isolation.cross_tenant_lookup_forbidden -eq $true) "IDEMPOTENCY_CROSS_TENANT_LOOKUP_ALLOWED"
Assert-Condition ($boundary.audit.delivery -eq "transactional_outbox" -and $boundary.audit.async_persistence -eq $true) "IDEMPOTENCY_AUDIT_ASYNC_BOUNDARY_INVALID"
Assert-Condition ($boundary.configuration_lifecycle.versioned -eq $true -and $boundary.configuration_lifecycle.rollback_required -eq $true) "IDEMPOTENCY_VERSION_ROLLBACK_MISSING"
Assert-Condition ($boundary.observability.raw_idempotency_key_forbidden -eq $true) "IDEMPOTENCY_KEY_DISCLOSURE_GUARD_MISSING"
Assert-Condition ($policySchema.properties.decision_status.const -eq "TBD-005") "IDEMPOTENCY_POLICY_TBD_GUARD_MISSING"
foreach ($field in @(
    "version",
    "tenant_id",
    "revision",
    "effective_at",
    "rollback_revision",
    "content_hash",
    "transport_header_name",
    "ttl_seconds",
    "storage_profile_ref",
    "replay_response_strategy",
    "conflict_response_strategy",
    "store_failure_strategy"
)) {
    Assert-Condition (@($policySchema.required) -contains $field) "IDEMPOTENCY_POLICY_FIELD_MISSING"
}

$records = @{}
$baseRequest = [PSCustomObject][ordered]@{
    schema_version = 1
    request_id = "request-idempotency-test"
    trace_id = "trace-idempotency-test"
    tenant_id = "tenant-a"
    authenticated_subject_id = "subject-a"
    operation_id = "publishModel"
    resource_id = "model-smart-chat"
    idempotency_key = "sensitive-test-key"
    request_fingerprint = "sha256:fingerprint-a"
    config_version = 42
}

$first = Invoke-ReferenceIdempotencyBoundary (Copy-ContractObject $baseRequest) $records
Assert-Condition ($first.outcome -eq "proceed" -and $first.reason_code -eq "IDEMPOTENCY_PROCEED") "IDEMPOTENCY_FIRST_REQUEST_NOT_ACCEPTED"
$duplicate = Invoke-ReferenceIdempotencyBoundary (Copy-ContractObject $baseRequest) $records
Assert-Condition ($duplicate.outcome -eq "duplicate" -and $duplicate.reason_code -eq "IDEMPOTENCY_DUPLICATE") "IDEMPOTENCY_DUPLICATE_NOT_DETECTED"

$conflicting = Copy-ContractObject $baseRequest
$conflicting.request_fingerprint = "sha256:fingerprint-b"
$conflict = Invoke-ReferenceIdempotencyBoundary $conflicting $records
Assert-Condition ($conflict.outcome -eq "conflict" -and $conflict.reason_code -eq "IDEMPOTENCY_KEY_FINGERPRINT_CONFLICT") "IDEMPOTENCY_CONFLICT_NOT_DETECTED"

$tenantB = Copy-ContractObject $baseRequest
$tenantB.tenant_id = "tenant-b"
$tenantDecision = Invoke-ReferenceIdempotencyBoundary $tenantB $records
Assert-Condition ($tenantDecision.outcome -eq "proceed") "IDEMPOTENCY_TENANT_SCOPE_COLLISION"
Assert-Condition ($tenantDecision.tenant_id -eq "tenant-b" -and $tenantDecision.config_version -eq 42) "IDEMPOTENCY_TRACE_CONTEXT_LOST"

foreach ($decision in @($first, $duplicate, $conflict, $tenantDecision)) {
    $serialized = $decision | ConvertTo-Json -Depth 10 -Compress
    Assert-Condition (-not $serialized.Contains([string]$baseRequest.idempotency_key)) "IDEMPOTENCY_KEY_DISCLOSED"
    Assert-Condition ($decision.audit_required -eq $true) "IDEMPOTENCY_AUDIT_REQUIREMENT_LOST"
}

Write-Output "status=pass reason_code=ADMIN_IDEMPOTENCY_CONTRACT_OK tbd=TBD-005 runtime=not-selected"
