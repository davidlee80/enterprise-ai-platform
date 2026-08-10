[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ownershipRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $ownershipRoot)

function Read-JsonFile {
    param([string]$Name)
    $path = Join-Path $ownershipRoot $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "OWNERSHIP_FILE_MISSING: $path" }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Assert-Condition {
    param([bool]$Condition, [string]$ReasonCode)
    if (-not $Condition) { throw $ReasonCode }
}

$schema = Read-JsonFile "ownership-record.v1.schema.json"
$catalog = Read-JsonFile "ownership-catalog.v1.json"
$boundary = Read-JsonFile "ownership-boundary.v1.json"
$baseline = Read-JsonFile "ownership-compatibility-baseline.v1.json"

Assert-Condition ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema" -and $schema.additionalProperties -eq $false) "OWNERSHIP_SCHEMA_INVALID"
Assert-Condition ($schema.'$id' -eq $baseline.record_schema_id) "OWNERSHIP_SCHEMA_ID_CHANGED"
foreach ($field in @($baseline.required_record_fields)) {
    Assert-Condition (@($schema.required) -contains [string]$field) "OWNERSHIP_RECORD_FIELD_REMOVED"
}
Assert-Condition ($catalog.status -eq "metadata-ready-owner-names-unconfigured" -and $catalog.decision_status -eq "TBD-018") "OWNERSHIP_CATALOG_STATUS_INVALID"
foreach ($field in @($baseline.required_unresolved_catalog_fields)) {
    Assert-Condition ($null -eq $catalog.$field) "OWNERSHIP_NAME_PREMATURELY_SELECTED"
}

$records = @($catalog.components)
Assert-Condition (@($records.component_id | Select-Object -Unique).Count -eq $records.Count) "OWNERSHIP_COMPONENT_DUPLICATE"
foreach ($componentId in @($baseline.required_component_ids)) {
    $matches = @($records | Where-Object { $_.component_id -eq $componentId })
    Assert-Condition ($matches.Count -eq 1) "OWNERSHIP_COMPONENT_MISSING"
}
Assert-Condition ($records.Count -eq @($baseline.required_component_ids).Count) "OWNERSHIP_COMPONENT_UNKNOWN"

foreach ($record in $records) {
    Assert-Condition ($null -eq $record.owner_ref -and $record.owner_status -eq "TBD-018") "OWNERSHIP_OWNER_PREMATURELY_SELECTED"
    Assert-Condition ($record.slo_ref -eq "ops/slo/README.md" -and $record.runbook_ref -eq "ops/runbooks/README.md") "OWNERSHIP_OPERATIONAL_LINK_MISSING"
    Assert-Condition ($null -eq $record.upgrade_window_ref -and $null -eq $record.data_retention_responsibility_ref) "OWNERSHIP_OPERATIONAL_ASSIGNMENT_PREMATURELY_SELECTED"
    $componentReadme = Join-Path $repoRoot ($record.component_path + "/README.md")
    Assert-Condition (Test-Path -LiteralPath $componentReadme -PathType Leaf) "OWNERSHIP_COMPONENT_README_MISSING"
    $readme = Get-Content -LiteralPath $componentReadme -Raw -Encoding UTF8
    foreach ($metadataLabel in @("Owner", "SLO", "Runbook", "Upgrade window", "Data retention responsibility")) {
        Assert-Condition ($readme.Contains($metadataLabel)) "OWNERSHIP_README_METADATA_MISSING"
    }
    Assert-Condition ($readme.Contains("TBD-018")) "OWNERSHIP_README_PLACEHOLDER_MISSING"
}

Assert-Condition ($boundary.status -eq "metadata-ready-owner-names-unconfigured" -and $boundary.decision_status -eq "TBD-018") "OWNERSHIP_BOUNDARY_STATUS_INVALID"
foreach ($property in @($boundary.current_assignment.PSObject.Properties)) {
    Assert-Condition ($null -eq $property.Value) "OWNERSHIP_ASSIGNMENT_PREMATURELY_SELECTED"
}
Assert-Condition ($boundary.validation.every_application_required -eq $true -and
    $boundary.validation.every_shared_package_required -eq $true -and
    $boundary.validation.duplicate_component_allowed -eq $false -and
    $boundary.validation.unknown_component_allowed -eq $false -and
    $boundary.validation.owner_name_required_before_production -eq $true -and
    $boundary.validation.placeholder_is_production_assignment -eq $false) "OWNERSHIP_VALIDATION_GUARD_INVALID"
Assert-Condition ($boundary.lifecycle.versioned -eq $true -and $boundary.lifecycle.replacement_preserves_prior_catalog -eq $true) "OWNERSHIP_REPLACEMENT_GUARD_MISSING"

Write-Output "status=pass reason_code=OWNERSHIP_METADATA_PLACEHOLDER_OK tbd=TBD-018 components=13 owner_names=unconfigured team_topology=unconfigured"
