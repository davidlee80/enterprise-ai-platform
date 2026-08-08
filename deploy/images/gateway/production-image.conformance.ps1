[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$boundaryRelativePath = "deploy/images/gateway/production-image-boundary.v1.json"
$boundaryPath = Join-Path $repoRoot $boundaryRelativePath
$failures = [System.Collections.Generic.List[object]]::new()

function Add-ConformanceFailure {
    param(
        [string]$ReasonCode,
        [string]$Subject,
        [string]$Detail
    )

    $failures.Add([PSCustomObject]@{
        ReasonCode = $ReasonCode
        Subject = $Subject
        Detail = $Detail
    })
}

if (-not (Test-Path -LiteralPath $boundaryPath -PathType Leaf)) {
    Write-Output "status=fail reason_code=PRODUCTION_IMAGE_BOUNDARY_MISSING subject=$boundaryRelativePath"
    exit 1
}

try {
    $boundary = Get-Content -LiteralPath $boundaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    Write-Output ("status=fail reason_code=PRODUCTION_IMAGE_BOUNDARY_JSON_INVALID subject={0} detail={1}" -f $boundaryRelativePath, $_.Exception.Message)
    exit 1
}

if ($boundary.schema_version -ne 1 -or $boundary.task -ne "TASK-M3-001" -or $boundary.component -ne "gateway") {
    Add-ConformanceFailure "PRODUCTION_IMAGE_IDENTITY_INVALID" $boundaryRelativePath "schema version, task, or component identity is invalid"
}

foreach ($name in @(
    "multi_stage",
    "digest_pinned_base_images",
    "minimal_runtime",
    "numeric_non_root_user",
    "locked_dependencies",
    "explicit_artifact_copy",
    "secret_free_layers",
    "secret_free_cache"
)) {
    if ($boundary.requirements.$name -ne $true) {
        Add-ConformanceFailure "PRODUCTION_IMAGE_REQUIREMENT_DISABLED" $name "mandatory production-image control must be true"
    }
}

if ($boundary.health.port -ne 8080 -or
    $boundary.health.liveness_path -ne "/healthz" -or
    $boundary.health.readiness_path -ne "/readyz") {
    Add-ConformanceFailure "PRODUCTION_IMAGE_HEALTH_CONTRACT_INVALID" $boundaryRelativePath "Gateway must expose port 8080 with /healthz and /readyz"
}

$expectedLabels = @(
    "org.opencontainers.image.source",
    "org.opencontainers.image.revision",
    "org.opencontainers.image.version"
)
foreach ($label in $expectedLabels) {
    if (@($boundary.traceability.required_oci_labels) -notcontains $label) {
        Add-ConformanceFailure "PRODUCTION_IMAGE_TRACEABILITY_LABEL_MISSING" $label "required OCI traceability label is absent"
    }
}
if ($null -ne $boundary.traceability.image_tag_format -or $boundary.traceability.image_tag_format_status -ne "TBD-013") {
    Add-ConformanceFailure "IMAGE_TAG_TBD_OVERRIDDEN" $boundaryRelativePath "the exact image tag format must remain unresolved under TBD-013"
}

if ($boundary.supply_chain.sbom_required -ne $true -or
    $boundary.supply_chain.ci_artifact_required -ne $true -or
    $boundary.supply_chain.signature_capability_required -ne $true) {
    Add-ConformanceFailure "PRODUCTION_IMAGE_SUPPLY_CHAIN_REQUIREMENT_DISABLED" $boundaryRelativePath "SBOM artifact and signing capability requirements are mandatory"
}

$dockerfilePath = Join-Path $repoRoot $boundary.dockerfile

if ($boundary.status -in @("runtime-implemented-supply-chain-tbd", "implemented-v1")) {
    if ($boundary.status -eq "implemented-v1" -and @($boundary.blocked_by).Count -ne 0) {
        Add-ConformanceFailure "IMPLEMENTED_IMAGE_HAS_BLOCKERS" $boundaryRelativePath "implemented boundary cannot retain blockers"
    }
    if ($boundary.status -eq "runtime-implemented-supply-chain-tbd" -and
        (@($boundary.blocked_by).Count -ne 2 -or
        @($boundary.blocked_by) -notcontains "REQ-CICD-004" -or
        @($boundary.blocked_by) -notcontains "TASK-CICD-001")) {
        Add-ConformanceFailure "RUNTIME_IMAGE_SUPPLY_CHAIN_BLOCKER_INVALID" $boundaryRelativePath "runtime-ready state must retain scanner/signing task blockers"
    }

    foreach ($property in $boundary.runtime_selection.PSObject.Properties) {
        if ($null -eq $property.Value -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            Add-ConformanceFailure "PRODUCTION_RUNTIME_SELECTION_INCOMPLETE" $property.Name "implemented image requires an explicit reviewed value"
        }
    }

    if ($null -eq $boundary.build_context -or [string]::IsNullOrWhiteSpace([string]$boundary.build_context)) {
        Add-ConformanceFailure "PRODUCTION_BUILD_CONTEXT_MISSING" $boundaryRelativePath "implemented image requires an explicit build context"
    }
    if (-not (Test-Path -LiteralPath $dockerfilePath -PathType Leaf)) {
        Add-ConformanceFailure "PRODUCTION_DOCKERFILE_MISSING" $boundary.dockerfile "implemented boundary references a missing Dockerfile"
    }

    $lockFilePath = Join-Path $repoRoot $boundary.runtime_selection.dependency_lock_file
    if (-not (Test-Path -LiteralPath $lockFilePath -PathType Leaf)) {
        Add-ConformanceFailure "DEPENDENCY_LOCK_FILE_MISSING" $boundary.runtime_selection.dependency_lock_file "selected dependency lock file does not exist"
    }

    if (Test-Path -LiteralPath $dockerfilePath -PathType Leaf) {
        $dockerfile = Get-Content -LiteralPath $dockerfilePath -Raw -Encoding UTF8
        $fromLines = @([regex]::Matches($dockerfile, "(?im)^\s*FROM\s+([^\s]+)(?:\s+AS\s+([^\s]+))?\s*$"))
        if ($fromLines.Count -lt 2) {
            Add-ConformanceFailure "DOCKERFILE_NOT_MULTI_STAGE" $boundary.dockerfile "at least two FROM stages are required"
        }
        $knownStages = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($match in $fromLines) {
            $imageReference = $match.Groups[1].Value
            if ($imageReference -notmatch "@sha256:[0-9a-fA-F]{64}$" -and
                -not $knownStages.Contains($imageReference)) {
                Add-ConformanceFailure "DOCKERFILE_BASE_IMAGE_NOT_DIGEST_PINNED" $imageReference "every external base image must be pinned by sha256 digest"
            }
            if ($match.Groups[2].Success) {
                $null = $knownStages.Add($match.Groups[2].Value)
            }
        }
        foreach ($imageField in @("build_image", "runtime_image")) {
            $selectedImage = [string]$boundary.runtime_selection.$imageField
            if ($dockerfile.IndexOf($selectedImage, [System.StringComparison]::Ordinal) -lt 0) {
                Add-ConformanceFailure "DOCKERFILE_RUNTIME_SELECTION_MISMATCH" $imageField "Dockerfile must use the digest-pinned image selected by ADR-001 boundary"
            }
        }
        if ($dockerfile -notmatch "(?im)^\s*COPY\s+--from=") {
            Add-ConformanceFailure "DOCKERFILE_ARTIFACT_COPY_MISSING" $boundary.dockerfile "runtime stage must copy an explicit build artifact"
        }
        if ($dockerfile -notmatch "(?im)^\s*RUN\s+--mount=type=cache," -or
            $dockerfile -notmatch "(?im)^\s*\s*--locked-mode\s*\\?\s*$") {
            Add-ConformanceFailure "DOCKERFILE_LOCKED_CACHED_RESTORE_MISSING" $boundary.dockerfile "build must use a dependency cache and locked-mode restore"
        }
        if ($dockerfile -match "(?i)--mount=type=secret") {
            Add-ConformanceFailure "DOCKERFILE_SECRET_MOUNT_FORBIDDEN" $boundary.dockerfile "Gateway image build does not accept Secret mounts"
        }
        if ($dockerfile -notmatch "(?im)^\s*EXPOSE\s+8080\s*$") {
            Add-ConformanceFailure "DOCKERFILE_GATEWAY_PORT_MISSING" $boundary.dockerfile "Gateway must expose port 8080"
        }
        if ($dockerfile -notmatch "(?im)^\s*HEALTHCHECK\s+" -or $dockerfile -notmatch "/healthz") {
            Add-ConformanceFailure "DOCKERFILE_HEALTHCHECK_MISSING" $boundary.dockerfile "Docker health check must target /healthz"
        }
        if ($dockerfile -notmatch '(?im)^\s*ENTRYPOINT\s+\["dotnet",\s*"EnterpriseAiPlatform\.Gateway\.dll"\]\s*$') {
            Add-ConformanceFailure "DOCKERFILE_ENTRYPOINT_INVALID" $boundary.dockerfile "runtime entrypoint must execute the selected Gateway artifact"
        }
        foreach ($label in $expectedLabels) {
            if ($dockerfile.IndexOf($label, [System.StringComparison]::Ordinal) -lt 0) {
                Add-ConformanceFailure "DOCKERFILE_TRACEABILITY_LABEL_MISSING" $label "required OCI label is absent"
            }
        }
        if ($dockerfile -match "(?im)^\s*(ARG|ENV)\s+[^\r\n]*(secret|token|password|passwd|api[_-]?key|provider[_-]?key)") {
            Add-ConformanceFailure "DOCKERFILE_CREDENTIAL_INPUT_FORBIDDEN" $boundary.dockerfile "credential-shaped ARG or ENV is forbidden"
        }

        $lastFrom = $dockerfile.LastIndexOf("`nFROM ", [System.StringComparison]::OrdinalIgnoreCase)
        if ($lastFrom -lt 0 -and $dockerfile.StartsWith("FROM ", [System.StringComparison]::OrdinalIgnoreCase)) {
            $lastFrom = 0
        }
        $runtimeStage = if ($lastFrom -ge 0) { $dockerfile.Substring($lastFrom) } else { $dockerfile }
        if ($runtimeStage -match "(?im)^\s*RUN\s+[^\r\n]*(apt-get|apk|dnf|yum|pip|npm|pnpm|yarn|nuget)\b") {
            Add-ConformanceFailure "DOCKERFILE_RUNTIME_PACKAGE_INSTALL_FORBIDDEN" $boundary.dockerfile "final runtime stage must not install packages"
        }
        $users = @([regex]::Matches($runtimeStage, "(?im)^\s*USER\s+([^\s]+)\s*$"))
        if ($users.Count -eq 0 -or $users[-1].Groups[1].Value -notmatch "^[1-9][0-9]*(?::[1-9][0-9]*)?$") {
            Add-ConformanceFailure "DOCKERFILE_FINAL_USER_NOT_NUMERIC_NON_ROOT" $boundary.dockerfile "final USER must be a numeric non-zero uid or uid:gid"
        }
    }

    if ($boundary.status -eq "runtime-implemented-supply-chain-tbd") {
        foreach ($name in @("sbom_generator", "image_scanner", "signing_provider")) {
            if ($null -ne $boundary.supply_chain.$name) {
                Add-ConformanceFailure "SUPPLY_CHAIN_TOOL_SELECTION_LEAKED" $name "tool selection remains TBD until REQ-CICD-004/TASK-CICD-001"
            }
        }
        foreach ($property in $boundary.acceptance_evidence.PSObject.Properties) {
            if ($null -ne $property.Value) {
                Add-ConformanceFailure "UNVERIFIED_IMAGE_EVIDENCE_CLAIMED" $property.Name "acceptance evidence must remain null until Linux image jobs run"
            }
        }
    }
    else {
        foreach ($name in @("sbom_generator", "image_scanner", "signing_provider")) {
            if ($null -eq $boundary.supply_chain.$name -or [string]::IsNullOrWhiteSpace([string]$boundary.supply_chain.$name)) {
                Add-ConformanceFailure "SUPPLY_CHAIN_TOOLING_INCOMPLETE" $name "implemented image requires reviewed SBOM, scanner, and signing tooling"
            }
        }
    }
}
else {
    Add-ConformanceFailure "PRODUCTION_IMAGE_STATUS_INVALID" $boundary.status "status must be runtime-implemented-supply-chain-tbd or implemented-v1 after ADR-001"
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Output ("status=fail reason_code={0} subject={1} detail={2}" -f $failure.ReasonCode, $failure.Subject, $failure.Detail)
    }
    exit 1
}

if ($boundary.status -eq "runtime-implemented-supply-chain-tbd") {
    Write-Output "status=pass reason_code=PRODUCTION_IMAGE_RUNTIME_STATIC_OK readiness=runtime-implemented blocked_by=REQ-CICD-004,TASK-CICD-001 acceptance=not-met"
}
else {
    Write-Output "status=pass reason_code=PRODUCTION_IMAGE_STATIC_CONFORMANCE_OK readiness=implemented acceptance=runtime-evidence-required"
}
