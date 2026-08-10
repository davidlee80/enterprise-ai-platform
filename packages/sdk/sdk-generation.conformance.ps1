[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$contractRoot = Join-Path $PSScriptRoot "contracts"
$schemaPath = Join-Path $contractRoot "sdk-generation-plan.v1.schema.json"
$boundaryPath = Join-Path $contractRoot "sdk-generation-boundary.v1.json"
$baselinePath = Join-Path $contractRoot "sdk-generation-compatibility-baseline.v1.json"
$openApiPath = Join-Path $repoRoot "docs/contracts/openapi/openapi.yaml"
$generatorPath = Join-Path $PSScriptRoot "generate.ps1"

function Read-ContractJson {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "SDK_PIPELINE_FILE_MISSING: $Path"
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

$schema = Read-ContractJson $schemaPath
$boundary = Read-ContractJson $boundaryPath
$baseline = Read-ContractJson $baselinePath
$openApi = Read-ContractJson $openApiPath

Assert-Condition ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "SDK_PIPELINE_SCHEMA_DRAFT_INVALID"
Assert-Condition ($schema.'$id' -eq $baseline.plan_schema_id) "SDK_PIPELINE_SCHEMA_ID_CHANGED"
Assert-Condition ($schema.additionalProperties -eq $false) "SDK_PIPELINE_UNVERSIONED_EXTENSION_ALLOWED"
foreach ($field in @($baseline.required_plan_fields)) {
    Assert-Condition (@($schema.required) -contains [string]$field) "SDK_PIPELINE_REQUIRED_FIELD_REMOVED"
}

Assert-Condition ($boundary.decision_status -eq "TBD-007") "SDK_LANGUAGE_DECISION_TRACE_MISSING"
Assert-Condition ($null -eq $boundary.language_set) "SDK_LANGUAGE_SET_PREMATURELY_SELECTED"
Assert-Condition ($null -eq $boundary.generator -and $null -eq $boundary.generator_version) "SDK_GENERATOR_PREMATURELY_SELECTED"
Assert-Condition ($null -eq $boundary.output_root -and $null -eq $boundary.package_registry) "SDK_OUTPUT_OR_REGISTRY_PREMATURELY_SELECTED"
Assert-Condition ($boundary.source_contract -eq "docs/contracts/openapi/openapi.yaml") "SDK_SOURCE_CONTRACT_INVALID"
Assert-Condition ($boundary.source_contract_version -eq $openApi.info.version) "SDK_SOURCE_VERSION_MISMATCH"
Assert-Condition ($boundary.input_hash_algorithm -eq "SHA256") "SDK_INPUT_HASH_ALGORITHM_INVALID"
Assert-Condition ($boundary.compatibility_required -eq $true) "SDK_COMPATIBILITY_GATE_DISABLED"
Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$boundary.rollback_rule)) "SDK_ROLLBACK_RULE_MISSING"

$stageNames = @($boundary.stages.name)
Assert-Condition (@($stageNames | Sort-Object -Unique).Count -eq $stageNames.Count) "SDK_PIPELINE_DUPLICATE_STAGE"
foreach ($stageName in @($baseline.required_ready_stages)) {
    $stage = @($boundary.stages | Where-Object { $_.name -eq $stageName })
    Assert-Condition ($stage.Count -eq 1 -and $stage[0].enabled -eq $true -and $stage[0].status -eq "ready" -and $null -eq $stage[0].blocked_by) "SDK_PIPELINE_READY_STAGE_INVALID"
}
foreach ($stageName in @($baseline.required_blocked_stages)) {
    $stage = @($boundary.stages | Where-Object { $_.name -eq $stageName })
    Assert-Condition ($stage.Count -eq 1 -and $stage[0].enabled -eq $false -and $stage[0].status -eq "blocked" -and $stage[0].blocked_by -eq "TBD-007") "SDK_PIPELINE_BLOCKED_STAGE_INVALID"
}

foreach ($command in @(
    [PSCustomObject]@{ Name = "validate"; Evidence = "status=pass command=validate reason_code=SDK_PIPELINE_CONTRACT_OK" },
    [PSCustomObject]@{ Name = "plan"; Evidence = "status=pass command=plan reason_code=SDK_GENERATION_ENTRYPOINT_OK" }
)) {
    $output = @(& $generatorPath $command.Name)
    foreach ($line in $output) { Write-Output $line }
    Assert-Condition ($output -contains $command.Evidence) "SDK_PIPELINE_COMMAND_EVIDENCE_MISSING"
}

$inputHash = (Get-FileHash -LiteralPath $openApiPath -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-Condition ($inputHash -match '^[a-f0-9]{64}$') "SDK_INPUT_DIGEST_INVALID"

Write-Output ("status=pass reason_code=SDK_GENERATION_PIPELINE_OK tbd=TBD-007 language_set=not-selected generator=not-selected input_sha256={0}" -f $inputHash)
