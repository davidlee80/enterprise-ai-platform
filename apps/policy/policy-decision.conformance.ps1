[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$contractRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "docs/contracts/policy-decisions"
$requestSchemaPath = Join-Path $contractRoot "policy-evaluation-request.v1.schema.json"
$decisionSchemaPath = Join-Path $contractRoot "policy-decision.v1.schema.json"
$boundaryPath = Join-Path $contractRoot "policy-boundary.v1.json"

function Read-ContractJson {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing policy contract: $Path"
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

function Copy-ContractObject {
    param([object]$Value)

    return $Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json
}

function New-PolicyDecision {
    param(
        [object]$Request,
        [string]$Outcome,
        [string]$ReasonCode,
        [object[]]$Obligations,
        [string[]]$MatchedPolicyIds
    )

    $allow = $null
    $denyReason = $null
    if ($Outcome -eq "allow") {
        $allow = $true
    }
    elseif ($Outcome -eq "deny") {
        $allow = $false
        $denyReason = $ReasonCode
    }

    return [PSCustomObject][ordered]@{
        schema_version = 1
        request_id = [string]$Request.request_id
        trace_id = [string]$Request.trace_id
        tenant_id = [string]$Request.tenant_id
        config_version = [int]$Request.config_version
        model_alias = [string]$Request.resource.model_alias
        outcome = $Outcome
        allow = $allow
        reason_code = $ReasonCode
        deny_reason = $denyReason
        obligations = @($Obligations)
        matched_policy_ids = @($MatchedPolicyIds)
        policy_version = $Request.policy_context.policy_version
    }
}

function Invoke-ReferencePolicyBoundary {
    param(
        [object]$Request,
        [bool]$RuntimeAvailable = $true
    )

    if (-not $RuntimeAvailable) {
        return New-PolicyDecision $Request "indeterminate" "POLICY_RUNTIME_UNAVAILABLE" @() @()
    }
    if ([string]$Request.tenant_id -ne [string]$Request.principal.tenant_id -or
        [string]$Request.tenant_id -ne [string]$Request.policy_context.tenant_id) {
        return New-PolicyDecision $Request "deny" "TENANT_MISMATCH" @() @()
    }
    if ([int]$Request.config_version -ne [int]$Request.policy_context.config_version) {
        return New-PolicyDecision $Request "indeterminate" "POLICY_CONTEXT_VERSION_MISMATCH" @() @()
    }

    $policyIds = @($Request.policy_context.policy_ids)
    if ([string]$Request.policy_context.tenant_status -ne "active") {
        return New-PolicyDecision $Request "deny" "TENANT_INACTIVE" @() @($policyIds | Select-Object -First 1)
    }
    if (@($Request.policy_context.allowed_models) -notcontains [string]$Request.resource.model_alias) {
        return New-PolicyDecision $Request "deny" "MODEL_NOT_ALLOWED" @() @($policyIds | Select-Object -First 1)
    }
    if (@($Request.policy_context.allowed_regions) -notcontains [string]$Request.resource.region) {
        return New-PolicyDecision $Request "deny" "REGION_NOT_ALLOWED" @() @($policyIds | Select-Object -First 1)
    }
    $projectedSpend = [decimal]$Request.policy_context.budget.month_spend + [decimal]$Request.resource.estimated_cost
    if ($projectedSpend -gt [decimal]$Request.policy_context.budget.month_limit) {
        return New-PolicyDecision $Request "deny" "BUDGET_LIMIT_EXCEEDED" @() @($policyIds | Select-Object -First 1)
    }

    return New-PolicyDecision $Request "allow" "POLICY_ALLOWED" @($Request.policy_context.obligations) $policyIds
}

$requestSchema = Read-ContractJson $requestSchemaPath
$decisionSchema = Read-ContractJson $decisionSchemaPath
$boundary = Read-ContractJson $boundaryPath

Assert-Condition ($requestSchema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "POLICY_REQUEST_SCHEMA_DRAFT_INVALID"
Assert-Condition ($decisionSchema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "POLICY_DECISION_SCHEMA_DRAFT_INVALID"
Assert-Condition ($requestSchema.additionalProperties -eq $false) "POLICY_REQUEST_UNVERSIONED_EXTENSION_ALLOWED"
Assert-Condition ($decisionSchema.additionalProperties -eq $false) "POLICY_DECISION_UNVERSIONED_EXTENSION_ALLOWED"
Assert-Condition ($boundary.runtime_status -eq "TBD-004" -and $null -eq $boundary.runtime) "POLICY_RUNTIME_PREMATURELY_SELECTED"
Assert-Condition ($boundary.indeterminate_handling.status -eq "TBD-017" -and $null -eq $boundary.indeterminate_handling.mapping) "POLICY_FAILURE_DEFAULT_PREMATURELY_SELECTED"

$obligations = @(
    [PSCustomObject]@{ kind = "mask"; target = "input.email" },
    [PSCustomObject]@{ kind = "redact"; target = "output.secret" },
    [PSCustomObject]@{ kind = "force_region"; region = "cn-north" },
    [PSCustomObject]@{ kind = "disable_body_logging"; enabled = $true },
    [PSCustomObject]@{ kind = "limit_max_tokens"; max_tokens = 1024 }
)

$baseRequest = [PSCustomObject]@{
    schema_version = 1
    request_id = "request-policy-test"
    trace_id = "trace-policy-test"
    tenant_id = "tenant-verified"
    config_version = 42
    principal = [PSCustomObject]@{
        subject_id = "subject-policy-test"
        tenant_id = "tenant-verified"
        scopes = @("chat:invoke")
    }
    resource = [PSCustomObject]@{
        model_alias = "smart-chat"
        region = "cn-north"
        estimated_cost = 10
    }
    policy_context = [PSCustomObject]@{
        tenant_id = "tenant-verified"
        config_version = 42
        policy_version = 7
        policy_ids = @("p_tenant", "p_model", "p_region", "p_budget", "p_obligations")
        tenant_status = "active"
        allowed_models = @("smart-chat")
        allowed_regions = @("cn-north")
        budget = [PSCustomObject]@{
            month_spend = 90
            month_limit = 100
        }
        obligations = $obligations
    }
}

$allowDecision = Invoke-ReferencePolicyBoundary (Copy-ContractObject $baseRequest)
Assert-Condition ($allowDecision.outcome -eq "allow" -and $allowDecision.allow -eq $true) "POLICY_VALID_REQUEST_NOT_ALLOWED"
Assert-Condition ($null -eq $allowDecision.deny_reason) "POLICY_ALLOW_HAS_DENY_REASON"
Assert-Condition ($allowDecision.tenant_id -eq "tenant-verified" -and $allowDecision.config_version -eq 42) "POLICY_TRACE_CONTEXT_LOST"
Assert-Condition (@($allowDecision.matched_policy_ids).Count -eq 5 -and $allowDecision.policy_version -eq 7) "POLICY_MATCH_METADATA_LOST"
foreach ($kind in @("mask", "redact", "force_region", "disable_body_logging", "limit_max_tokens")) {
    Assert-Condition (@($allowDecision.obligations.kind) -contains $kind) ("POLICY_OBLIGATION_MISSING_" + $kind.ToUpperInvariant())
}

foreach ($scenario in @(
    [PSCustomObject]@{ Name = "inactive"; Reason = "TENANT_INACTIVE"; Mutate = { param($r) $r.policy_context.tenant_status = "suspended" } },
    [PSCustomObject]@{ Name = "model"; Reason = "MODEL_NOT_ALLOWED"; Mutate = { param($r) $r.resource.model_alias = "blocked-model" } },
    [PSCustomObject]@{ Name = "region"; Reason = "REGION_NOT_ALLOWED"; Mutate = { param($r) $r.resource.region = "unapproved-region" } },
    [PSCustomObject]@{ Name = "budget"; Reason = "BUDGET_LIMIT_EXCEEDED"; Mutate = { param($r) $r.resource.estimated_cost = 10.01 } },
    [PSCustomObject]@{ Name = "tenant"; Reason = "TENANT_MISMATCH"; Mutate = { param($r) $r.principal.tenant_id = "tenant-other" } }
)) {
    $request = Copy-ContractObject $baseRequest
    & $scenario.Mutate $request
    $decision = Invoke-ReferencePolicyBoundary $request
    Assert-Condition ($decision.outcome -eq "deny" -and $decision.allow -eq $false) ("POLICY_DENY_SCENARIO_ALLOWED_" + $scenario.Name)
    Assert-Condition ($decision.reason_code -eq $scenario.Reason -and $decision.deny_reason -eq $scenario.Reason) ("POLICY_DENY_REASON_INVALID_" + $scenario.Name)
}

$versionMismatch = Copy-ContractObject $baseRequest
$versionMismatch.policy_context.config_version = 41
$versionDecision = Invoke-ReferencePolicyBoundary $versionMismatch
Assert-Condition ($versionDecision.outcome -eq "indeterminate" -and $null -eq $versionDecision.allow) "POLICY_VERSION_MISMATCH_NOT_INDETERMINATE"
Assert-Condition ($versionDecision.reason_code -eq "POLICY_CONTEXT_VERSION_MISMATCH") "POLICY_VERSION_MISMATCH_REASON_INVALID"

$unavailableDecision = Invoke-ReferencePolicyBoundary (Copy-ContractObject $baseRequest) $false
Assert-Condition ($unavailableDecision.outcome -eq "indeterminate" -and $null -eq $unavailableDecision.allow) "POLICY_RUNTIME_FAILURE_NOT_INDETERMINATE"
Assert-Condition ($unavailableDecision.reason_code -eq "POLICY_RUNTIME_UNAVAILABLE") "POLICY_RUNTIME_FAILURE_REASON_INVALID"

$serializedDecision = $allowDecision | ConvertTo-Json -Depth 20 -Compress
foreach ($forbidden in @("policy_source", "provider_key", "internal_endpoint", "prompt", "response_body", "subject-policy-test")) {
    Assert-Condition (-not $serializedDecision.ToLowerInvariant().Contains($forbidden)) ("POLICY_DECISION_DISCLOSURE_" + $forbidden.ToUpperInvariant())
}

Write-Output "status=pass reason_code=POLICY_DECISION_CONFORMANCE_OK"
