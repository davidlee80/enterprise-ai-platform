[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$chartPath = $PSScriptRoot
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

function Invoke-HelmSuccess {
    param(
        [string]$Subject,
        [string[]]$Arguments
    )

    $output = @(& helm @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Add-ConformanceFailure "HELM_COMMAND_FAILED" $Subject (($output | Out-String).Trim())
        return ""
    }
    return (($output | Out-String).Trim())
}

function Assert-RenderedMatch {
    param(
        [string]$Rendered,
        [string]$Pattern,
        [string]$ReasonCode,
        [string]$Detail
    )

    if ($Rendered -notmatch $Pattern) {
        Add-ConformanceFailure $ReasonCode "rendered-manifest" $Detail
    }
}

if ($null -eq (Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Output "status=fail reason_code=HELM_NOT_AVAILABLE detail=install Helm v3.21.3 or use the pinned PR workflow setup step"
    exit 1
}

$helmVersion = (& helm version --short 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    Write-Output "status=fail reason_code=HELM_VERSION_FAILED"
    exit 1
}

$null = Invoke-HelmSuccess "helm-lint-default" @("lint", $chartPath)
$defaultRendered = Invoke-HelmSuccess "helm-template-default" @("template", "gateway", $chartPath)
$devRendered = Invoke-HelmSuccess "helm-template-development" @(
    "template", "gateway", $chartPath,
    "--values", (Join-Path $chartPath "values-dev.yaml")
)
$testRendered = Invoke-HelmSuccess "helm-template-test" @(
    "template", "gateway", $chartPath,
    "--values", (Join-Path $chartPath "values-test.yaml")
)

$testDigest = "sha256:" + ("0" * 64)
$prodRendered = Invoke-HelmSuccess "helm-template-production" @(
    "template", "gateway", $chartPath,
    "--values", (Join-Path $chartPath "values-prod.yaml"),
    "--set-string", ("image.digest=" + $testDigest)
)

Assert-RenderedMatch $defaultRendered '(?m)^kind: Deployment\s*$' "HELM_GATEWAY_DEPLOYMENT_MISSING" "Deployment was not rendered"
Assert-RenderedMatch $defaultRendered '(?m)^kind: Service\s*$' "HELM_GATEWAY_SERVICE_MISSING" "Service was not rendered"
Assert-RenderedMatch $defaultRendered '(?m)^kind: PodDisruptionBudget\s*$' "HELM_GATEWAY_PDB_MISSING" "PodDisruptionBudget was not rendered"
Assert-RenderedMatch $defaultRendered '(?m)^\s+replicas: 3\s*$' "HELM_GATEWAY_DEFAULT_REPLICAS_INVALID" "default replica count must be 3"
Assert-RenderedMatch $defaultRendered '(?m)^\s+containerPort: 8080\s*$' "HELM_GATEWAY_PORT_INVALID" "container port must be 8080"
Assert-RenderedMatch $defaultRendered '(?m)^\s+path: /readyz\s*$' "HELM_GATEWAY_READINESS_INVALID" "readiness probe must use /readyz"
Assert-RenderedMatch $defaultRendered '(?m)^\s+path: /healthz\s*$' "HELM_GATEWAY_LIVENESS_INVALID" "liveness/startup probe must use /healthz"
Assert-RenderedMatch $defaultRendered '(?m)^\s+startupProbe:\s*$' "HELM_GATEWAY_STARTUP_PROBE_MISSING" "startup probe was not rendered"
Assert-RenderedMatch $defaultRendered '(?ms)^\s+requests:\s*\n\s+cpu: 500m\s*\n\s+memory: 512Mi\s*$' "HELM_GATEWAY_REQUESTS_INVALID" "baseline resource requests are invalid"
Assert-RenderedMatch $defaultRendered '(?ms)^\s+limits:\s*\n\s+cpu: "?2"?\s*\n\s+memory: 2Gi\s*$' "HELM_GATEWAY_LIMITS_INVALID" "baseline resource limits are invalid"
Assert-RenderedMatch $defaultRendered '(?m)^\s+automountServiceAccountToken: false\s*$' "HELM_SERVICE_ACCOUNT_TOKEN_GUARD_MISSING" "service account token must not be mounted"
Assert-RenderedMatch $defaultRendered '(?m)^\s+runAsNonRoot: true\s*$' "HELM_NON_ROOT_GUARD_MISSING" "non-root security context is missing"
Assert-RenderedMatch $defaultRendered '(?m)^\s+allowPrivilegeEscalation: false\s*$' "HELM_PRIVILEGE_GUARD_MISSING" "privilege escalation guard is missing"
Assert-RenderedMatch $defaultRendered '(?m)^\s+readOnlyRootFilesystem: true\s*$' "HELM_READ_ONLY_ROOT_GUARD_MISSING" "read-only root filesystem guard is missing"
Assert-RenderedMatch $defaultRendered '(?m)^\s+topologySpreadConstraints:\s*$' "HELM_TOPOLOGY_SPREAD_MISSING" "topology spread constraint is missing"
Assert-RenderedMatch $defaultRendered '(?m)^\s+type: RollingUpdate\s*$' "HELM_ROLLING_UPDATE_MISSING" "RollingUpdate strategy is missing"

if ($defaultRendered -match '(?m)^kind: Secret\s*$') {
    Add-ConformanceFailure "HELM_PLAINTEXT_SECRET_RESOURCE_FORBIDDEN" "rendered-manifest" "chart must not render Kubernetes Secret resources"
}
if ($defaultRendered -match '(?m)^\s+namespace:\s+\S+') {
    Add-ConformanceFailure "HELM_NAMESPACE_TBD_OVERRIDDEN" "rendered-manifest" "namespace must remain a release input under TBD-019"
}

Assert-RenderedMatch $devRendered '(?m)^\s+replicas: 1\s*$' "HELM_DEVELOPMENT_VALUES_INVALID" "development overlay must render one replica"
if ($devRendered -match '(?m)^kind: PodDisruptionBudget\s*$') {
    Add-ConformanceFailure "HELM_DEVELOPMENT_PDB_UNEXPECTED" "values-dev.yaml" "development overlay disables the PodDisruptionBudget"
}
Assert-RenderedMatch $testRendered '(?m)^\s+replicas: 2\s*$' "HELM_TEST_VALUES_INVALID" "test overlay must render two replicas"
Assert-RenderedMatch $testRendered '(?m)^\s+minAvailable: 1\s*$' "HELM_TEST_PDB_INVALID" "test overlay PDB must preserve one replica"
Assert-RenderedMatch $prodRendered '(?m)^\s+replicas: 3\s*$' "HELM_PRODUCTION_REPLICAS_INVALID" "production overlay must render three replicas"
Assert-RenderedMatch $prodRendered '(?m)^\s+minAvailable: 2\s*$' "HELM_PRODUCTION_PDB_INVALID" "production PDB must preserve two replicas"
Assert-RenderedMatch $prodRendered '(?m)^\s+whenUnsatisfiable: DoNotSchedule\s*$' "HELM_PRODUCTION_TOPOLOGY_INVALID" "production topology spread must be enforced"
Assert-RenderedMatch $prodRendered ([regex]::Escape("registry.example.com/ai-platform/gateway@" + $testDigest)) "HELM_PRODUCTION_DIGEST_INVALID" "production image must render by immutable digest"
if ($prodRendered -match '(?m)^\s+image:\s+"?[^\r\n]*:0\.0\.0-development"?\s*$') {
    Add-ConformanceFailure "HELM_PRODUCTION_DEVELOPMENT_IMAGE_FORBIDDEN" "values-prod.yaml" "production must not fall back to the development appVersion"
}

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$missingImageOutput = @(& helm template gateway $chartPath --values (Join-Path $chartPath "values-prod.yaml") 2>&1)
$missingImageExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
if ($missingImageExitCode -eq 0) {
    Add-ConformanceFailure "HELM_PRODUCTION_IMAGE_NOT_REQUIRED" "values-prod.yaml" "production render must fail without an explicit digest or tag"
}
elseif (($missingImageOutput | Out-String) -notmatch 'TBD-013') {
    Add-ConformanceFailure "HELM_PRODUCTION_IMAGE_FAILURE_UNSTRUCTURED" "values-prod.yaml" "missing-image failure did not explain the TBD-013 boundary"
}

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$conflictingImageOutput = @(& helm template gateway $chartPath --set-string "image.tag=test" --set-string ("image.digest=" + $testDigest) 2>&1)
$conflictingImageExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
if ($conflictingImageExitCode -eq 0) {
    Add-ConformanceFailure "HELM_IMAGE_REFERENCE_AMBIGUOUS" "values.yaml" "tag and digest must be mutually exclusive"
}
elseif (($conflictingImageOutput | Out-String) -notmatch 'image.tag and image.digest') {
    Add-ConformanceFailure "HELM_IMAGE_REFERENCE_FAILURE_UNSTRUCTURED" "values.yaml" "tag/digest conflict did not emit the expected failure"
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Output ("status=fail reason_code={0} subject={1} detail={2}" -f $failure.ReasonCode, $failure.Subject, $failure.Detail)
    }
    exit 1
}

Write-Output ("status=pass reason_code=GATEWAY_HELM_CONFORMANCE_OK helm={0} environments=development,test,production default_replicas=3 port=8080" -f $helmVersion)
