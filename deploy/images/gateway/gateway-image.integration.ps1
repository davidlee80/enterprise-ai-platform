[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$dockerfile = Join-Path $PSScriptRoot "Dockerfile"
$imageTag = "enterprise-ai-platform/gateway:pr-conformance"
$containerId = $null

function Fail-Integration {
    param(
        [string]$ReasonCode,
        [string]$Detail
    )

    Write-Output ("status=fail reason_code={0} detail={1}" -f $ReasonCode, $Detail)
    exit 1
}

if ($null -eq (Get-Command docker -ErrorAction SilentlyContinue)) {
    Fail-Integration "DOCKER_NOT_AVAILABLE" "Docker is required for Linux Gateway image evidence"
}

$sourceUrl = if ([string]::IsNullOrWhiteSpace($env:GITHUB_SERVER_URL) -or
    [string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY)) {
    "https://github.com/davidlee80/enterprise-ai-platform"
}
else {
    $env:GITHUB_SERVER_URL.TrimEnd('/') + "/" + $env:GITHUB_REPOSITORY
}
$sourceRevision = if ([string]::IsNullOrWhiteSpace($env:GITHUB_SHA)) {
    [string](& git -C $repoRoot rev-parse HEAD)
}
else {
    $env:GITHUB_SHA
}
$sourceVersion = "0.1.0-pr"

try {
    & docker build `
        --file $dockerfile `
        --tag $imageTag `
        --build-arg "SOURCE_URL=$sourceUrl" `
        --build-arg "SOURCE_REVISION=$sourceRevision" `
        --build-arg "SOURCE_VERSION=$sourceVersion" `
        $repoRoot
    if ($LASTEXITCODE -ne 0) {
        Fail-Integration "GATEWAY_IMAGE_BUILD_FAILED" "docker build failed"
    }

    $inspection = [string](& docker image inspect $imageTag --format '{{json .}}') | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or
        $inspection.Os -ne "linux" -or
        $inspection.Config.User -ne "1654:1654" -or
        $null -eq $inspection.Config.ExposedPorts.'8080/tcp' -or
        $inspection.Config.Labels.'org.opencontainers.image.source' -ne $sourceUrl -or
        $inspection.Config.Labels.'org.opencontainers.image.revision' -ne $sourceRevision -or
        $inspection.Config.Labels.'org.opencontainers.image.version' -ne $sourceVersion) {
        Fail-Integration "GATEWAY_IMAGE_INSPECTION_FAILED" "Linux OS, numeric user, port, or OCI labels are invalid"
    }

    $history = [string](& docker image history $imageTag --no-trunc)
    if ($LASTEXITCODE -ne 0) {
        Fail-Integration "GATEWAY_IMAGE_HISTORY_UNAVAILABLE" "docker history failed"
    }
    if ($history -match '(?i)(provider[_-]?key|api[_-]?key|password|passwd|secret|token)\s*=') {
        Fail-Integration "GATEWAY_IMAGE_HISTORY_CREDENTIAL_PATTERN" "credential-shaped assignment appeared in image history"
    }

    $containerId = [string](& docker run --detach --publish "127.0.0.1::8080" $imageTag)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($containerId)) {
        Fail-Integration "GATEWAY_CONTAINER_START_FAILED" "docker run failed"
    }
    $containerId = $containerId.Trim()

    $portOutput = [string](& docker port $containerId "8080/tcp")
    if ($LASTEXITCODE -ne 0 -or $portOutput -notmatch ':(\d+)\s*$') {
        Fail-Integration "GATEWAY_CONTAINER_PORT_UNAVAILABLE" "published Gateway port could not be resolved"
    }
    $hostPort = $Matches[1]

    $health = $null
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(30)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        try {
            $health = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$hostPort/healthz" -TimeoutSec 2
            if ($health.StatusCode -eq 200) {
                break
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }
    if ($null -eq $health -or $health.StatusCode -ne 200) {
        Fail-Integration "GATEWAY_CONTAINER_HEALTH_FAILED" "/healthz did not return 200"
    }

    try {
        $null = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$hostPort/readyz" -TimeoutSec 2
        Fail-Integration "GATEWAY_CONTAINER_READINESS_UNEXPECTED" "/readyz must not return success before a Runtime Snapshot is installed"
    }
    catch {
        $response = $_.Exception.Response
        if ($null -eq $response -or [int]$response.StatusCode -ne 503) {
            Fail-Integration "GATEWAY_CONTAINER_READINESS_FAILED" "/readyz did not return structured 503"
        }
    }

    $containerHealth = [string](& docker inspect $containerId --format '{{.State.Health.Status}}')
    $healthDeadline = [DateTimeOffset]::UtcNow.AddSeconds(40)
    while ($containerHealth.Trim() -ne "healthy" -and [DateTimeOffset]::UtcNow -lt $healthDeadline) {
        Start-Sleep -Seconds 1
        $containerHealth = [string](& docker inspect $containerId --format '{{.State.Health.Status}}')
    }
    if ($containerHealth.Trim() -ne "healthy") {
        Fail-Integration "GATEWAY_DOCKER_HEALTHCHECK_FAILED" "image HEALTHCHECK did not reach healthy"
    }
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($containerId)) {
        & docker rm --force $containerId | Out-Null
    }
    & docker image rm --force $imageTag | Out-Null
}

Write-Output "status=pass reason_code=GATEWAY_LINUX_IMAGE_INTEGRATION_OK os=linux user=1654:1654 port=8080 health=/healthz readiness=/readyz"
