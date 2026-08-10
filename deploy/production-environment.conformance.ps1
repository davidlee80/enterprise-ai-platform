[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$deployRoot = $PSScriptRoot
$contractRoot = Join-Path $deployRoot "contracts"

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "PRODUCTION_ENVIRONMENT_FILE_MISSING: $Path" }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Assert-Condition {
    param([bool]$Condition, [string]$ReasonCode)
    if (-not $Condition) { throw $ReasonCode }
}

function Test-ProductionSettings {
    param([object]$Settings)
    $values = @($Settings.domain, $Settings.namespace, $Settings.certificate_issuer, $Settings.storage_class)
    $configuredCount = @($values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
    if ($configuredCount -eq 0) { return "PRODUCTION_ENVIRONMENT_SETTINGS_UNCONFIGURED" }
    if ($configuredCount -ne $values.Count) { return "PRODUCTION_ENVIRONMENT_SETTING_MISSING" }
    return "PRODUCTION_ENVIRONMENT_SETTINGS_READY"
}

$schema = Read-JsonFile (Join-Path $contractRoot "production-environment-settings.v1.schema.json")
$boundary = Read-JsonFile (Join-Path $contractRoot "production-environment-boundary.v1.json")
$baseline = Read-JsonFile (Join-Path $contractRoot "production-environment-compatibility-baseline.v1.json")
$valuesSchema = Read-JsonFile (Join-Path $deployRoot "helm/gateway/values.schema.json")

Assert-Condition ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema" -and $schema.additionalProperties -eq $false) "PRODUCTION_ENVIRONMENT_SCHEMA_INVALID"
Assert-Condition ($schema.'$id' -eq $baseline.settings_schema_id) "PRODUCTION_ENVIRONMENT_SCHEMA_ID_CHANGED"
foreach ($field in @($baseline.required_setting_fields)) { Assert-Condition (@($schema.required) -contains [string]$field) "PRODUCTION_ENVIRONMENT_SETTING_FIELD_REMOVED" }
Assert-Condition ($schema.properties.decision_status.const -eq "TBD-019") "PRODUCTION_ENVIRONMENT_TBD_GUARD_MISSING"
foreach ($field in @("domain", "namespace", "certificate_issuer", "storage_class")) { Assert-Condition (@($schema.properties.$field.type) -contains "null") "PRODUCTION_ENVIRONMENT_NULL_SETTING_NOT_SUPPORTED" }

Assert-Condition ($boundary.status -eq "variables-ready-production-values-unconfigured" -and $boundary.decision_status -eq "TBD-019") "PRODUCTION_ENVIRONMENT_BOUNDARY_STATUS_INVALID"
foreach ($field in @($baseline.required_unresolved_fields)) { Assert-Condition ($null -eq $boundary.current_settings.$field) "PRODUCTION_ENVIRONMENT_VALUE_PREMATURELY_SELECTED" }
Assert-Condition ($boundary.helm_binding.values_must_remain_empty_in_repository -eq $true -and
    $boundary.terraform_binding.defaults_must_remain_null_in_repository -eq $true -and
    $boundary.publication_guard.reviewed_settings_required_for_production -eq $true -and
    $boundary.publication_guard.fixture_values_are_production_values -eq $false -and
    $boundary.publication_guard.secret_values_allowed -eq $false -and
    $boundary.publication_guard.namespace_domain_or_storage_default_allowed -eq $false) "PRODUCTION_ENVIRONMENT_PUBLICATION_GUARD_INVALID"
Assert-Condition ($boundary.configuration_lifecycle.versioned -eq $true -and
    $boundary.configuration_lifecycle.revision_required -eq $true -and
    $boundary.configuration_lifecycle.rollback_target_required -eq $true -and
    $boundary.configuration_lifecycle.rollback_reuses_prior_reviewed_settings -eq $true) "PRODUCTION_ENVIRONMENT_ROLLBACK_GUARD_MISSING"

$productionValues = Get-Content -LiteralPath (Join-Path $deployRoot "helm/gateway/values-prod.yaml") -Raw -Encoding UTF8
$defaultValues = Get-Content -LiteralPath (Join-Path $deployRoot "helm/gateway/values.yaml") -Raw -Encoding UTF8
foreach ($content in @($defaultValues, $productionValues)) {
    Assert-Condition ($content -match '(?ms)^production:\s*\r?\n\s+domain:\s*""\s*\r?\n\s+namespace:\s*""\s*\r?\n\s+certificateIssuer:\s*""\s*\r?\n\s+storageClass:\s*""') "HELM_PRODUCTION_ENVIRONMENT_VALUES_NOT_EMPTY"
}
Assert-Condition (@($valuesSchema.required) -contains "production") "HELM_PRODUCTION_ENVIRONMENT_OBJECT_NOT_REQUIRED"
foreach ($field in @("domain", "namespace", "certificateIssuer", "storageClass")) { Assert-Condition (@($valuesSchema.properties.production.required) -contains $field) "HELM_PRODUCTION_ENVIRONMENT_VALUE_MISSING" }

$terraformProd = Get-Content -LiteralPath (Join-Path $deployRoot "terraform/environments/prod/main.tf") -Raw -Encoding UTF8
foreach ($variableName in @($baseline.required_terraform_variables)) {
    Assert-Condition ($terraformProd -match ('(?ms)variable\s+"' + [regex]::Escape([string]$variableName) + '"\s*\{.*?default\s*=\s*null.*?nullable\s*=\s*true.*?\}')) "TERRAFORM_PRODUCTION_ENVIRONMENT_VARIABLE_INVALID"
}
foreach ($forbidden in @("aws_", "azurerm_", "google_", "cloudflare_")) { Assert-Condition (-not $terraformProd.ToLowerInvariant().Contains($forbidden)) "PRODUCTION_ENVIRONMENT_CLOUD_VENDOR_SELECTED" }

Assert-Condition ((Test-ProductionSettings $boundary.current_settings) -eq "PRODUCTION_ENVIRONMENT_SETTINGS_UNCONFIGURED") "PRODUCTION_ENVIRONMENT_UNCONFIGURED_STATE_INVALID"
# The values below are conformance fixtures and are not production defaults or recommendations.
$fixtureSettings = [PSCustomObject]@{ domain = "gateway.fixture.invalid"; namespace = "fixture-namespace"; certificate_issuer = "fixture-issuer"; storage_class = "fixture-storage" }
Assert-Condition ((Test-ProductionSettings $fixtureSettings) -eq "PRODUCTION_ENVIRONMENT_SETTINGS_READY") "PRODUCTION_ENVIRONMENT_FIXTURE_NOT_READY"
$partialSettings = [PSCustomObject]@{ domain = "gateway.fixture.invalid"; namespace = $null; certificate_issuer = "fixture-issuer"; storage_class = "fixture-storage" }
Assert-Condition ((Test-ProductionSettings $partialSettings) -eq "PRODUCTION_ENVIRONMENT_SETTING_MISSING") "PRODUCTION_ENVIRONMENT_PARTIAL_SETTINGS_ACCEPTED"

Write-Output "status=pass reason_code=PRODUCTION_ENVIRONMENT_VARIABLES_OK tbd=TBD-019 domain=unconfigured namespace=unconfigured certificate_issuer=unconfigured storage_class=unconfigured"
