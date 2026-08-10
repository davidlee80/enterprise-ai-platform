[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$imagesRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $imagesRoot)
$contractRoot = Join-Path $imagesRoot "contracts"

function Read-ContractJson {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "IMAGE_TRACEABILITY_CONTRACT_FILE_MISSING: $Path"
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

function Copy-ContractObject {
    param([object]$Value)

    return $Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json
}

function New-ValidationResult {
    param(
        [bool]$Valid,
        [string]$ReasonCode
    )

    return [PSCustomObject]@{
        valid = $Valid
        reason_code = $ReasonCode
    }
}

function Test-PublicationRecord {
    param(
        [object]$Record,
        [object]$Boundary,
        [string[]]$PlaceholderRevisions
    )

    foreach ($field in @("component", "image_repository", "image_digest", "source_repository", "source_revision", "source_version", "build_id", "built_at")) {
        if ([string]::IsNullOrWhiteSpace([string]$Record.$field)) {
            return New-ValidationResult $false "IMAGE_TRACEABILITY_FIELD_MISSING"
        }
    }
    if ([string]$Record.image_digest -notmatch '^sha256:[a-f0-9]{64}$') {
        return New-ValidationResult $false "IMAGE_DIGEST_INVALID"
    }
    if (@($PlaceholderRevisions) -contains ([string]$Record.source_revision).ToLowerInvariant()) {
        return New-ValidationResult $false "IMAGE_SOURCE_REVISION_PLACEHOLDER"
    }
    if ($Record.oci_labels.'org.opencontainers.image.source' -ne $Record.source_repository -or
        $Record.oci_labels.'org.opencontainers.image.revision' -ne $Record.source_revision -or
        $Record.oci_labels.'org.opencontainers.image.version' -ne $Record.source_version) {
        return New-ValidationResult $false "IMAGE_OCI_LABEL_RECORD_MISMATCH"
    }
    if ([string]$Record.publication_scope -eq "release" -and $null -ne $Record.image_tag) {
        if ($Boundary.publication_guard.production_tag_publication_enabled -ne $true -or
            $null -eq $Boundary.current_policy.active_policy_revision -or
            $null -eq $Record.tag_policy_revision) {
            return New-ValidationResult $false "IMAGE_TAG_POLICY_UNCONFIGURED"
        }
    }
    return New-ValidationResult $true "IMAGE_PUBLICATION_TRACEABILITY_OK"
}

$tagPolicySchema = Read-ContractJson (Join-Path $contractRoot "image-tag-policy.v1.schema.json")
$publicationSchema = Read-ContractJson (Join-Path $contractRoot "image-publication-record.v1.schema.json")
$boundary = Read-ContractJson (Join-Path $contractRoot "image-traceability-boundary.v1.json")
$baseline = Read-ContractJson (Join-Path $contractRoot "image-traceability-compatibility-baseline.v1.json")

foreach ($schema in @($tagPolicySchema, $publicationSchema)) {
    Assert-Condition ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "IMAGE_TRACEABILITY_SCHEMA_DRAFT_INVALID"
    Assert-Condition ($schema.additionalProperties -eq $false) "IMAGE_TRACEABILITY_SCHEMA_UNVERSIONED_EXTENSION_ALLOWED"
}
Assert-Condition ($tagPolicySchema.'$id' -eq $baseline.tag_policy_schema_id) "IMAGE_TAG_POLICY_SCHEMA_ID_CHANGED"
Assert-Condition ($publicationSchema.'$id' -eq $baseline.publication_record_schema_id) "IMAGE_PUBLICATION_SCHEMA_ID_CHANGED"
foreach ($field in @($baseline.required_tag_policy_fields)) {
    Assert-Condition (@($tagPolicySchema.required) -contains [string]$field) "IMAGE_TAG_POLICY_FIELD_REMOVED"
}
foreach ($field in @($baseline.required_publication_fields)) {
    Assert-Condition (@($publicationSchema.required) -contains [string]$field) "IMAGE_PUBLICATION_FIELD_REMOVED"
}
Assert-Condition ($tagPolicySchema.properties.decision_status.const -eq "TBD-013") "IMAGE_TAG_POLICY_TBD_GUARD_MISSING"
Assert-Condition (@($tagPolicySchema.properties.tag_format.type) -contains "null") "IMAGE_TAG_NULL_FORMAT_NOT_SUPPORTED"
foreach ($prematureConstraint in @("enum", "const", "pattern", "format")) {
    Assert-Condition (@($tagPolicySchema.properties.tag_format.PSObject.Properties.Name) -notcontains $prematureConstraint) "IMAGE_TAG_FORMAT_PREMATURELY_SELECTED"
}
Assert-Condition ($publicationSchema.properties.image_digest.pattern -eq "^sha256:[a-f0-9]{64}$") "IMAGE_PUBLICATION_DIGEST_GUARD_MISSING"
foreach ($label in @($baseline.required_oci_labels)) {
    Assert-Condition (@($publicationSchema.properties.oci_labels.required) -contains [string]$label) "IMAGE_PUBLICATION_OCI_LABEL_REMOVED"
}
$publicationProperties = @($publicationSchema.properties.PSObject.Properties.Name)
foreach ($forbiddenField in @("credential", "secret", "token", "password", "private_key")) {
    Assert-Condition ($publicationProperties -notcontains $forbiddenField) "IMAGE_PUBLICATION_SECRET_FIELD_FOUND"
}

Assert-Condition ($boundary.status -eq "traceability-ready-tag-format-unconfigured" -and $boundary.decision_status -eq "TBD-013") "IMAGE_TRACEABILITY_BOUNDARY_STATUS_INVALID"
foreach ($property in @($boundary.current_policy.PSObject.Properties)) {
    Assert-Condition ($null -eq $property.Value) "IMAGE_TAG_POLICY_PREMATURELY_SELECTED"
}
Assert-Condition ($boundary.traceability.source_repository_required -eq $true -and
    $boundary.traceability.source_revision_required -eq $true -and
    $boundary.traceability.source_version_required -eq $true -and
    $boundary.traceability.image_digest_required -eq $true -and
    $boundary.traceability.publication_record_required -eq $true -and
    $boundary.traceability.oci_labels_must_match_record -eq $true) "IMAGE_TRACEABILITY_REQUIREMENT_DISABLED"
Assert-Condition ($boundary.traceability.tag_is_locator_not_identity -eq $true -and
    $boundary.traceability.production_identity -eq "image-digest" -and
    $boundary.traceability.rollback_identity -eq "previously-verified-image-digest") "IMAGE_IMMUTABLE_IDENTITY_GUARD_MISSING"
Assert-Condition ($boundary.publication_guard.digest_only_release_record_allowed -eq $true -and
    $boundary.publication_guard.production_tag_publication_enabled -eq $false -and
    $boundary.publication_guard.tag_policy_revision_required_for_release_tag -eq $true -and
    $boundary.publication_guard.implicit_default_tag_allowed -eq $false -and
    $boundary.publication_guard.unreviewed_mutable_alias_allowed -eq $false -and
    $boundary.publication_guard.tag_format_validation_enabled -eq $false) "IMAGE_TAG_PUBLICATION_GUARD_INVALID"
Assert-Condition ($boundary.configuration_lifecycle.versioned -eq $true -and
    $boundary.configuration_lifecycle.rollback_required -eq $true) "IMAGE_TAG_POLICY_ROLLBACK_GUARD_MISSING"

$gatewayBoundaryPath = Join-Path $repoRoot "deploy/images/gateway/production-image-boundary.v1.json"
$gatewayBoundary = Read-ContractJson $gatewayBoundaryPath
Assert-Condition ($gatewayBoundary.traceability.contract -eq "deploy/images/contracts/image-traceability-boundary.v1.json") "GATEWAY_IMAGE_TRACEABILITY_CONTRACT_MISSING"
Assert-Condition ($null -eq $gatewayBoundary.traceability.image_tag_format -and $gatewayBoundary.traceability.image_tag_format_status -eq "TBD-013") "GATEWAY_IMAGE_TAG_FORMAT_PREMATURELY_SELECTED"

$dockerfilePath = Join-Path $repoRoot "deploy/images/gateway/Dockerfile"
$dockerfile = Get-Content -LiteralPath $dockerfilePath -Raw -Encoding UTF8
foreach ($argument in @("SOURCE_URL", "SOURCE_REVISION", "SOURCE_VERSION")) {
    Assert-Condition ($dockerfile -match ("(?m)^ARG " + $argument + "\s*$")) "IMAGE_TRACEABILITY_BUILD_ARGUMENT_MISSING"
    Assert-Condition ($dockerfile -notmatch ("(?m)^ARG " + $argument + "=")) "IMAGE_TRACEABILITY_BUILD_ARGUMENT_DEFAULT_FORBIDDEN"
}
Assert-Condition ($dockerfile.Contains('test -n "$SOURCE_URL"') -and
    $dockerfile.Contains('test -n "$SOURCE_REVISION"') -and
    $dockerfile.Contains('test "$SOURCE_REVISION" != "uncommitted"') -and
    $dockerfile.Contains('test -n "$SOURCE_VERSION"')) "IMAGE_TRACEABILITY_BUILD_ARGUMENT_VALIDATION_MISSING"
foreach ($label in @($baseline.required_oci_labels)) {
    Assert-Condition ($dockerfile.Contains([string]$label)) "IMAGE_TRACEABILITY_DOCKERFILE_LABEL_MISSING"
}

$integrationPath = Join-Path $repoRoot "deploy/images/gateway/gateway-image.integration.ps1"
$integrationContent = Get-Content -LiteralPath $integrationPath -Raw -Encoding UTF8
foreach ($argument in @("SOURCE_URL", "SOURCE_REVISION", "SOURCE_VERSION")) {
    Assert-Condition ($integrationContent.Contains("--build-arg `"$argument=")) "IMAGE_INTEGRATION_TRACEABILITY_ARGUMENT_MISSING"
}

$digest = "sha256:" + ("a" * 64)
$releaseRecord = [PSCustomObject]@{
    schema_version = 1
    status = "validated"
    publication_scope = "release"
    component = "fixture-component"
    image_repository = "registry.invalid/fixture/component"
    image_tag = $null
    image_digest = $digest
    source_repository = "https://source.invalid/fixture/repository"
    source_revision = "0123456789abcdef0123456789abcdef01234567"
    source_version = "fixture-version"
    build_id = "fixture-build"
    built_at = "2026-01-01T00:00:00Z"
    tag_policy_revision = $null
    oci_labels = [PSCustomObject]@{
        'org.opencontainers.image.source' = "https://source.invalid/fixture/repository"
        'org.opencontainers.image.revision' = "0123456789abcdef0123456789abcdef01234567"
        'org.opencontainers.image.version' = "fixture-version"
    }
    sbom_ref = $null
    provenance_ref = $null
    signature_ref = $null
}
$releaseResult = Test-PublicationRecord $releaseRecord $boundary @($baseline.forbidden_placeholder_revisions)
Assert-Condition ($releaseResult.valid -eq $true -and $releaseResult.reason_code -eq "IMAGE_PUBLICATION_TRACEABILITY_OK") "IMAGE_DIGEST_ONLY_RELEASE_RECORD_REJECTED"

$conformanceRecord = Copy-ContractObject $releaseRecord
$conformanceRecord.publication_scope = "conformance"
$conformanceRecord.image_tag = "fixture-tag"
$conformanceResult = Test-PublicationRecord $conformanceRecord $boundary @($baseline.forbidden_placeholder_revisions)
Assert-Condition ($conformanceResult.valid -eq $true) "IMAGE_TEST_ONLY_TAG_RECORD_REJECTED"

$unconfiguredReleaseTag = Copy-ContractObject $releaseRecord
$unconfiguredReleaseTag.image_tag = "fixture-release-tag"
$unconfiguredResult = Test-PublicationRecord $unconfiguredReleaseTag $boundary @($baseline.forbidden_placeholder_revisions)
Assert-Condition ($unconfiguredResult.valid -eq $false -and $unconfiguredResult.reason_code -eq "IMAGE_TAG_POLICY_UNCONFIGURED") "IMAGE_RELEASE_TAG_PUBLISHED_WITHOUT_POLICY"

$mismatchedRecord = Copy-ContractObject $releaseRecord
$mismatchedRecord.oci_labels.'org.opencontainers.image.revision' = "different-revision"
$mismatchResult = Test-PublicationRecord $mismatchedRecord $boundary @($baseline.forbidden_placeholder_revisions)
Assert-Condition ($mismatchResult.valid -eq $false -and $mismatchResult.reason_code -eq "IMAGE_OCI_LABEL_RECORD_MISMATCH") "IMAGE_LABEL_MISMATCH_ACCEPTED"

$placeholderRecord = Copy-ContractObject $releaseRecord
$placeholderRecord.source_revision = "uncommitted"
$placeholderRecord.oci_labels.'org.opencontainers.image.revision' = "uncommitted"
$placeholderResult = Test-PublicationRecord $placeholderRecord $boundary @($baseline.forbidden_placeholder_revisions)
Assert-Condition ($placeholderResult.valid -eq $false -and $placeholderResult.reason_code -eq "IMAGE_SOURCE_REVISION_PLACEHOLDER") "IMAGE_PLACEHOLDER_REVISION_ACCEPTED"

$invalidDigestRecord = Copy-ContractObject $releaseRecord
$invalidDigestRecord.image_digest = "sha256:not-a-digest"
$invalidDigestResult = Test-PublicationRecord $invalidDigestRecord $boundary @($baseline.forbidden_placeholder_revisions)
Assert-Condition ($invalidDigestResult.valid -eq $false -and $invalidDigestResult.reason_code -eq "IMAGE_DIGEST_INVALID") "IMAGE_INVALID_DIGEST_ACCEPTED"

Write-Output "status=pass reason_code=IMAGE_TRACEABILITY_CONTRACT_OK tbd=TBD-013 tag_format=unselected production_tag_publication=blocked digest_traceability=ready"
