[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$contractRoot = Join-Path $PSScriptRoot "contracts"
$requestSchemaPath = Join-Path $contractRoot "authentication-request.v1.schema.json"
$decisionSchemaPath = Join-Path $contractRoot "authentication-decision.v1.schema.json"
$boundaryPath = Join-Path $contractRoot "authentication-boundary.v1.json"

function Read-ContractJson {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing authentication contract: $Path"
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

function New-NonAuthenticatedDecision {
    param(
        [string]$Outcome,
        [string]$ReasonCode
    )

    return [PSCustomObject][ordered]@{
        schema_version = 1
        outcome = $Outcome
        reason_code = $ReasonCode
    }
}

function Invoke-ReferenceAuthenticationBoundary {
    param(
        [object]$Request,
        [scriptblock]$Verifier
    )

    $candidates = @($Request.credential_candidates)
    if ($candidates.Count -eq 0) {
        return New-NonAuthenticatedDecision "denied" "CREDENTIAL_MISSING"
    }
    if ($candidates.Count -ne 1) {
        return New-NonAuthenticatedDecision "denied" "CREDENTIAL_AMBIGUOUS"
    }

    $candidate = $candidates[0]
    if (@("bearer", "api_key") -notcontains [string]$candidate.kind -or
        [string]::IsNullOrWhiteSpace([string]$candidate.value)) {
        return New-NonAuthenticatedDecision "denied" "CREDENTIAL_MALFORMED"
    }

    $verification = & $Verifier $candidate
    switch ([string]$verification.status) {
        "valid" {
            $subjectProperty = $verification.PSObject.Properties["subject_id"]
            $tenantProperty = $verification.PSObject.Properties["tenant_id"]
            $scopesProperty = $verification.PSObject.Properties["scopes"]
            $scopes = if ($null -eq $scopesProperty) { @() } else { @($scopesProperty.Value) }
            if ($null -eq $subjectProperty -or
                $null -eq $tenantProperty -or
                [string]::IsNullOrWhiteSpace([string]$subjectProperty.Value) -or
                [string]::IsNullOrWhiteSpace([string]$tenantProperty.Value) -or
                @($scopes | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
                return New-NonAuthenticatedDecision "indeterminate" "AUTHENTICATOR_RESULT_INVALID"
            }
            $principal = [ordered]@{
                subject_id = [string]$subjectProperty.Value
                tenant_id = [string]$tenantProperty.Value
                credential_kind = [string]$candidate.kind
                scopes = $scopes
            }
            $credentialIdProperty = $verification.PSObject.Properties["credential_id"]
            if ($null -ne $credentialIdProperty -and -not [string]::IsNullOrWhiteSpace([string]$credentialIdProperty.Value)) {
                $principal["credential_id"] = [string]$credentialIdProperty.Value
            }
            return [PSCustomObject][ordered]@{
                schema_version = 1
                outcome = "authenticated"
                reason_code = "AUTHENTICATED"
                principal = [PSCustomObject]$principal
            }
        }
        "invalid" { return New-NonAuthenticatedDecision "denied" "CREDENTIAL_INVALID" }
        "expired" { return New-NonAuthenticatedDecision "denied" "CREDENTIAL_EXPIRED" }
        "revoked" { return New-NonAuthenticatedDecision "denied" "CREDENTIAL_REVOKED" }
        default { return New-NonAuthenticatedDecision "indeterminate" "AUTHENTICATOR_UNAVAILABLE" }
    }
}

$requestSchema = Read-ContractJson $requestSchemaPath
$decisionSchema = Read-ContractJson $decisionSchemaPath
$boundary = Read-ContractJson $boundaryPath

Assert-Condition ($requestSchema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "AUTH_REQUEST_SCHEMA_DRAFT_INVALID"
Assert-Condition ($decisionSchema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "AUTH_DECISION_SCHEMA_DRAFT_INVALID"
Assert-Condition ($requestSchema.additionalProperties -eq $false) "AUTH_REQUEST_UNVERSIONED_EXTENSION_ALLOWED"
Assert-Condition ($decisionSchema.additionalProperties -eq $false) "AUTH_DECISION_UNVERSIONED_EXTENSION_ALLOWED"
Assert-Condition ($null -eq $requestSchema.properties.request.properties.PSObject.Properties["tenant_id"]) "AUTH_CLIENT_TENANT_OVERRIDE_ALLOWED"
Assert-Condition (@($boundary.supported_credential_kinds) -contains "bearer") "AUTH_BEARER_CAPABILITY_MISSING"
Assert-Condition (@($boundary.supported_credential_kinds) -contains "api_key") "AUTH_API_KEY_CAPABILITY_MISSING"

$bearerValue = "bearer-" + [Guid]::NewGuid().ToString("N")
$apiValue = "api-" + [Guid]::NewGuid().ToString("N")
$invalidValue = "invalid-" + [Guid]::NewGuid().ToString("N")
$expiredValue = "expired-" + [Guid]::NewGuid().ToString("N")
$revokedValue = "revoked-" + [Guid]::NewGuid().ToString("N")
$unavailableValue = "unavailable-" + [Guid]::NewGuid().ToString("N")
$invalidResultValue = "invalid-result-" + [Guid]::NewGuid().ToString("N")

$verifier = {
    param([object]$Candidate)

    $status = switch ([string]$Candidate.value) {
        $bearerValue { "valid" }
        $apiValue { "valid" }
        $expiredValue { "expired" }
        $revokedValue { "revoked" }
        $unavailableValue { "unavailable" }
        default { "invalid" }
    }
    if ([string]$Candidate.value -eq $invalidResultValue) {
        return [PSCustomObject]@{
            status = "valid"
            subject_id = ""
            tenant_id = ""
            scopes = @()
        }
    }
    if ($status -ne "valid") {
        return [PSCustomObject]@{ status = $status }
    }
    return [PSCustomObject]@{
        status = "valid"
        subject_id = "subject-test"
        tenant_id = "tenant-verified"
        scopes = @("chat:invoke")
        credential_id = "credential-test"
    }
}

function New-TestRequest {
    param([object[]]$Candidates)

    return [PSCustomObject]@{
        schema_version = 1
        request = [PSCustomObject]@{
            method = "POST"
            path = "/v1/chat/completions"
        }
        credential_candidates = @($Candidates)
    }
}

$bearerDecision = Invoke-ReferenceAuthenticationBoundary (New-TestRequest @([PSCustomObject]@{ kind = "bearer"; value = $bearerValue })) $verifier
Assert-Condition ($bearerDecision.outcome -eq "authenticated") "AUTH_BEARER_REJECTED"
Assert-Condition ($bearerDecision.principal.tenant_id -eq "tenant-verified") "AUTH_TENANT_NOT_VERIFIER_BOUND"
Assert-Condition ($bearerDecision.principal.credential_kind -eq "bearer") "AUTH_BEARER_KIND_LOST"

$apiDecision = Invoke-ReferenceAuthenticationBoundary (New-TestRequest @([PSCustomObject]@{ kind = "api_key"; value = $apiValue })) $verifier
Assert-Condition ($apiDecision.outcome -eq "authenticated") "AUTH_API_KEY_REJECTED"
Assert-Condition ($apiDecision.principal.credential_kind -eq "api_key") "AUTH_API_KEY_KIND_LOST"

$missingDecision = Invoke-ReferenceAuthenticationBoundary (New-TestRequest @()) $verifier
Assert-Condition ($missingDecision.reason_code -eq "CREDENTIAL_MISSING") "AUTH_MISSING_CREDENTIAL_ACCEPTED"

$ambiguousDecision = Invoke-ReferenceAuthenticationBoundary (New-TestRequest @(
    [PSCustomObject]@{ kind = "bearer"; value = $bearerValue },
    [PSCustomObject]@{ kind = "api_key"; value = $apiValue }
)) $verifier
Assert-Condition ($ambiguousDecision.reason_code -eq "CREDENTIAL_AMBIGUOUS") "AUTH_AMBIGUOUS_CREDENTIAL_ACCEPTED"

$malformedDecision = Invoke-ReferenceAuthenticationBoundary (New-TestRequest @([PSCustomObject]@{ kind = "bearer"; value = " " })) $verifier
Assert-Condition ($malformedDecision.reason_code -eq "CREDENTIAL_MALFORMED") "AUTH_MALFORMED_CREDENTIAL_ACCEPTED"

foreach ($scenario in @(
    [PSCustomObject]@{ Value = $invalidValue; Outcome = "denied"; Reason = "CREDENTIAL_INVALID" },
    [PSCustomObject]@{ Value = $expiredValue; Outcome = "denied"; Reason = "CREDENTIAL_EXPIRED" },
    [PSCustomObject]@{ Value = $revokedValue; Outcome = "denied"; Reason = "CREDENTIAL_REVOKED" },
    [PSCustomObject]@{ Value = $unavailableValue; Outcome = "indeterminate"; Reason = "AUTHENTICATOR_UNAVAILABLE" },
    [PSCustomObject]@{ Value = $invalidResultValue; Outcome = "indeterminate"; Reason = "AUTHENTICATOR_RESULT_INVALID" }
)) {
    $decision = Invoke-ReferenceAuthenticationBoundary (New-TestRequest @([PSCustomObject]@{ kind = "bearer"; value = $scenario.Value })) $verifier
    Assert-Condition ($decision.outcome -eq $scenario.Outcome -and $decision.reason_code -eq $scenario.Reason) ("AUTH_SCENARIO_FAILED_" + $scenario.Reason)
    Assert-Condition ($null -eq $decision.PSObject.Properties["principal"]) ("AUTH_NON_SUCCESS_PRINCIPAL_LEAKED_" + $scenario.Reason)
}

$serializedDecisions = @($bearerDecision, $apiDecision, $missingDecision, $ambiguousDecision, $malformedDecision) | ConvertTo-Json -Depth 8 -Compress
foreach ($value in @($bearerValue, $apiValue, $invalidValue, $expiredValue, $revokedValue, $unavailableValue, $invalidResultValue)) {
    Assert-Condition (-not $serializedDecisions.Contains($value)) "AUTH_CREDENTIAL_VALUE_LEAKED"
}

Write-Output "status=pass reason_code=AUTHENTICATION_BOUNDARY_CONFORMANCE_OK"
