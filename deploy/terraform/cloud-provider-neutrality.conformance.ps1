[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$terraformRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $terraformRoot)
$contractRoot = Join-Path $terraformRoot "contracts"
$schemaPath = Join-Path $contractRoot "cloud-provider-selection.v1.schema.json"
$boundaryPath = Join-Path $contractRoot "cloud-provider-boundary.v1.json"
$baselinePath = Join-Path $contractRoot "cloud-provider-compatibility-baseline.v1.json"

function Read-ContractJson {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "CLOUD_PROVIDER_CONTRACT_FILE_MISSING: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
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

Assert-Condition ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "CLOUD_PROVIDER_SCHEMA_DRAFT_INVALID"
Assert-Condition ($schema.'$id' -eq $baseline.selection_schema_id) "CLOUD_PROVIDER_SCHEMA_ID_CHANGED"
Assert-Condition ($schema.additionalProperties -eq $false) "CLOUD_PROVIDER_SCHEMA_UNVERSIONED_EXTENSION_ALLOWED"
foreach ($field in @($baseline.required_selection_fields)) {
    Assert-Condition (@($schema.required) -contains [string]$field) "CLOUD_PROVIDER_SELECTION_FIELD_REMOVED"
}
Assert-Condition ($schema.properties.decision_status.const -eq "TBD-011") "CLOUD_PROVIDER_TBD_GUARD_MISSING"
Assert-Condition (@($schema.properties.provider_id.type) -contains "null") "CLOUD_PROVIDER_SELECTION_NULL_NOT_SUPPORTED"
Assert-Condition (@($schema.properties.provider_id.PSObject.Properties.Name) -notcontains "enum") "CLOUD_PROVIDER_ENUM_PREMATURELY_SELECTED"

$adapterSchema = $schema.properties.capability_adapter_refs
Assert-Condition ($adapterSchema.additionalProperties -eq $false) "CLOUD_PROVIDER_ADAPTER_EXTENSION_UNVERSIONED"
foreach ($capability in @($baseline.required_capabilities)) {
    Assert-Condition (@($adapterSchema.required) -contains [string]$capability) "CLOUD_PROVIDER_CAPABILITY_ADAPTER_REMOVED"
    Assert-Condition (@($adapterSchema.properties.$capability.type) -contains "null") "CLOUD_PROVIDER_CAPABILITY_ADAPTER_NULL_NOT_SUPPORTED"
}

Assert-Condition ($boundary.status -eq "provider-selection-unresolved" -and $boundary.decision_status -eq "TBD-011") "CLOUD_PROVIDER_BOUNDARY_STATUS_INVALID"
foreach ($property in @($boundary.current_selection.PSObject.Properties)) {
    Assert-Condition ($null -eq $property.Value) "CLOUD_PROVIDER_SELECTION_PREMATURELY_PUBLISHED"
}
foreach ($capability in @($baseline.required_capabilities)) {
    Assert-Condition ($null -eq $boundary.capability_adapter_refs.$capability) "CLOUD_PROVIDER_ADAPTER_PREMATURELY_PUBLISHED"
}
Assert-Condition ($boundary.core_topology.module_source_policy -eq "repository-local-only") "CLOUD_PROVIDER_LOCAL_MODULE_POLICY_MISSING"
Assert-Condition ($boundary.core_topology.selection_cardinality -eq "one-or-more-reviewed-bindings" -and
    $boundary.core_topology.single_provider_architecture_required -eq $false) "CLOUD_PROVIDER_SINGLE_CLOUD_ASSUMPTION_FOUND"
Assert-Condition ($boundary.core_topology.provider_blocks_allowed -eq $false -and
    $boundary.core_topology.provider_resources_allowed -eq $false -and
    $boundary.core_topology.provider_data_sources_allowed -eq $false -and
    $boundary.core_topology.remote_backend_allowed -eq $false -and
    $boundary.core_topology.required_providers_allowed -eq $false) "CLOUD_PROVIDER_CORE_TOPOLOGY_GUARD_MISSING"
Assert-Condition ($boundary.execution_guard.contract_validation_enabled -eq $true -and
    $boundary.execution_guard.provider_plan_enabled -eq $false -and
    $boundary.execution_guard.provider_apply_enabled -eq $false) "CLOUD_PROVIDER_EXECUTION_GUARD_INVALID"
Assert-Condition ($boundary.configuration_lifecycle.versioned -eq $true -and
    $boundary.configuration_lifecycle.rollback_required -eq $true) "CLOUD_PROVIDER_ROLLBACK_GUARD_MISSING"
Assert-Condition ($boundary.security.plaintext_credentials_forbidden -eq $true -and
    $boundary.security.credential_outputs_forbidden -eq $true -and
    $boundary.security.state_files_forbidden_in_repository -eq $true) "CLOUD_PROVIDER_SECRET_STATE_GUARD_MISSING"

$terraformFiles = @(Get-ChildItem -LiteralPath $terraformRoot -Recurse -Filter "*.tf" -File)
Assert-Condition ($terraformFiles.Count -gt 0) "CLOUD_PROVIDER_TERRAFORM_FILES_MISSING"
$vendorPattern = "(?i)(?<![A-Za-z0-9])(" + ((@($baseline.forbidden_vendor_tokens) | ForEach-Object { [regex]::Escape([string]$_) }) -join "|") + ")(?![A-Za-z0-9])"
foreach ($file in $terraformFiles) {
    $relativePath = $file.FullName.Substring($terraformRoot.Length + 1).Replace("\", "/")
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    if ($content -match '(?m)^\s*(provider|resource|data)\s+"') {
        throw "CLOUD_PROVIDER_IMPLEMENTATION_BLOCK_FOUND: $relativePath"
    }
    if ($content -match '(?m)^\s*backend\s+"' -or $content -match '(?m)^\s*required_providers\s*\{') {
        throw "CLOUD_PROVIDER_CONFIGURATION_BLOCK_FOUND: $relativePath"
    }
    if ($content -match $vendorPattern) {
        throw "CLOUD_PROVIDER_VENDOR_TOKEN_FOUND: $relativePath"
    }
    if ($content -match '(?im)^\s*(password|api_key|provider_key|access_token|private_key)\s*=') {
        throw "CLOUD_PROVIDER_PLAINTEXT_CREDENTIAL_FOUND: $relativePath"
    }
    foreach ($sourceMatch in [regex]::Matches($content, '(?m)^\s*source\s*=\s*"([^"]+)"')) {
        $moduleSource = $sourceMatch.Groups[1].Value
        Assert-Condition ($moduleSource.StartsWith(".", [System.StringComparison]::Ordinal)) "CLOUD_PROVIDER_REMOTE_MODULE_SOURCE_FOUND"
        $resolvedModuleSource = [System.IO.Path]::GetFullPath((Join-Path $file.DirectoryName $moduleSource))
        Assert-Condition ($resolvedModuleSource.StartsWith(($repoRoot + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)) "CLOUD_PROVIDER_MODULE_SOURCE_OUTSIDE_REPOSITORY"
        Assert-Condition (Test-Path -LiteralPath $resolvedModuleSource -PathType Container) "CLOUD_PROVIDER_LOCAL_MODULE_SOURCE_MISSING"
    }
}

foreach ($capability in @($baseline.required_capabilities)) {
    $moduleName = if ($capability -eq "object_storage") { "object-storage" } else { $capability }
    $modulePath = Join-Path $terraformRoot "modules/$moduleName/main.tf"
    Assert-Condition (Test-Path -LiteralPath $modulePath -PathType Leaf) "CLOUD_PROVIDER_CAPABILITY_MODULE_MISSING"
    $moduleContent = Get-Content -LiteralPath $modulePath -Raw -Encoding UTF8
    Assert-Condition ($moduleContent.Contains('provider_status') -or $moduleContent.Contains('cloud_provider_status')) "CLOUD_PROVIDER_MODULE_STATUS_GUARD_MISSING"
    Assert-Condition ($moduleContent.Contains('TBD-011')) "CLOUD_PROVIDER_MODULE_TBD_MARKER_MISSING"
}

foreach ($environment in @($baseline.required_environments)) {
    $environmentRoot = Join-Path $terraformRoot "environments/$environment"
    Assert-Condition (Test-Path -LiteralPath $environmentRoot -PathType Container) "CLOUD_PROVIDER_ENVIRONMENT_ROOT_MISSING"
    $mainContent = Get-Content -LiteralPath (Join-Path $environmentRoot "main.tf") -Raw -Encoding UTF8
    Assert-Condition ($mainContent.Contains('source = "../../modules/platform-environment"')) "CLOUD_PROVIDER_ENVIRONMENT_COMPOSITION_CHANGED"
}

$forbiddenRepositoryState = @(Get-ChildItem -LiteralPath $terraformRoot -Recurse -File | Where-Object {
    $_.Name -eq ".terraform.lock.hcl" -or $_.Name -match '\.tfstate(?:\.backup)?$'
})
Assert-Condition ($forbiddenRepositoryState.Count -eq 0) "CLOUD_PROVIDER_STATE_OR_LOCK_FILE_FOUND"

Write-Output "status=pass reason_code=CLOUD_PROVIDER_NEUTRALITY_OK tbd=TBD-011 provider=unselected adapters=unbound backend=unselected"
