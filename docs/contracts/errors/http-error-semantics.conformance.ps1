[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$boundaryPath = Join-Path $PSScriptRoot "http-error-semantics-boundary.v1.json"
$baselinePath = Join-Path $PSScriptRoot "http-error-semantics-compatibility-baseline.v1.json"
$openApiPath = Join-Path $repoRoot "docs/contracts/openapi/openapi.yaml"

function Read-ContractJson {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "HTTP_ERROR_SEMANTICS_FILE_MISSING: $Path"
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

function Get-PropertyValue {
    param(
        [object]$InputObject,
        [string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

$boundary = Read-ContractJson $boundaryPath
$baseline = Read-ContractJson $baselinePath
$openApi = Read-ContractJson $openApiPath

Assert-Condition ($boundary.status -eq "http-status-semantics-only") "HTTP_ERROR_BOUNDARY_STATUS_INVALID"
Assert-Condition (@($boundary.requirements) -contains "TBD-008") "HTTP_ERROR_TBD_TRACE_MISSING"
Assert-Condition ($boundary.source_contract_version -eq $openApi.info.version -and $boundary.source_contract_version -eq $baseline.source_contract_version) "HTTP_ERROR_SOURCE_VERSION_MISMATCH"
Assert-Condition ($boundary.public_body.status -eq "TBD-008") "HTTP_ERROR_BODY_TBD_STATUS_INVALID"
Assert-Condition ($null -eq $boundary.public_body.schema -and
    $null -eq $boundary.public_body.media_type -and
    $null -eq $boundary.public_body.error_code_field -and
    $null -eq $boundary.public_body.message_field -and
    $null -eq $boundary.public_body.correlation_fields) "HTTP_ERROR_BODY_PREMATURELY_DEFINED"
Assert-Condition ($boundary.status_402.status -eq "TBD-008" -and $null -eq $boundary.status_402.enabled -and $null -eq $boundary.status_402.meaning) "HTTP_402_PREMATURELY_DEFINED"
Assert-Condition ($boundary.internal_decision_context.structured_reason_code_required -eq $true) "HTTP_ERROR_INTERNAL_REASON_CODE_NOT_REQUIRED"
Assert-Condition ($null -eq $boundary.internal_decision_context.public_error_code_mapping) "HTTP_ERROR_CODE_MAPPING_PREMATURELY_DEFINED"
Assert-Condition ($boundary.compatibility.status_removal_or_meaning_change_is_breaking -eq $true) "HTTP_ERROR_COMPATIBILITY_GUARD_MISSING"

$operation = $openApi.paths.'/v1/chat/completions'.post
$responses = $operation.responses
foreach ($property in $baseline.required_http_semantics.PSObject.Properties) {
    $status = [string]$property.Name
    $meaning = [string]$property.Value
    $response = Get-PropertyValue $responses $status
    Assert-Condition ($null -ne $response) "HTTP_ERROR_REQUIRED_STATUS_MISSING"
    Assert-Condition ([string]$response.description -like ($meaning + "*")) "HTTP_ERROR_STATUS_MEANING_CHANGED"
    Assert-Condition ([string]$response.description -match 'TBD-008') "HTTP_ERROR_STATUS_TBD_TRACE_MISSING"
    Assert-Condition ($null -eq (Get-PropertyValue $response "content")) "HTTP_ERROR_BODY_PREMATURELY_PUBLISHED"

    $description = ([string]$response.description).ToLowerInvariant()
    foreach ($forbidden in @("provider key", "secret_ref", "internal endpoint", "policy source", "stack trace", "raw provider error")) {
        Assert-Condition (-not $description.Contains($forbidden)) "HTTP_ERROR_DESCRIPTION_DISCLOSURE"
    }
}
Assert-Condition ($null -eq (Get-PropertyValue $responses "402")) "HTTP_402_PREMATURELY_PUBLISHED"

$publishedSemantics = @{}
foreach ($item in @($boundary.required_http_semantics)) {
    $publishedSemantics[[string]$item.status] = [string]$item.meaning
}
foreach ($property in $baseline.required_http_semantics.PSObject.Properties) {
    Assert-Condition ($publishedSemantics[[string]$property.Name] -eq [string]$property.Value) "HTTP_ERROR_BOUNDARY_SEMANTIC_MISMATCH"
}

foreach ($field in @($boundary.internal_decision_context.required_fields)) {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$field)) "HTTP_ERROR_INTERNAL_CONTEXT_FIELD_INVALID"
}
foreach ($forbidden in @($baseline.forbidden_public_data)) {
    Assert-Condition (@($boundary.security.forbidden_public_data) -contains [string]$forbidden) "HTTP_ERROR_SECURITY_GUARD_REMOVED"
}

Write-Output "status=pass reason_code=HTTP_ERROR_STATUS_SEMANTICS_OK tbd=TBD-008 public_body=not-defined status_402=not-defined"
