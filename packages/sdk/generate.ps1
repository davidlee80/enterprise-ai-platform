[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("validate", "plan")]
    [string]$Command = "plan"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$openApiCommand = Join-Path $repoRoot "scripts/openapi.ps1"
$boundaryPath = Join-Path $PSScriptRoot "contracts/sdk-generation-boundary.v1.json"

if (-not (Test-Path -LiteralPath $boundaryPath -PathType Leaf)) {
    Write-Output "status=fail reason_code=SDK_PIPELINE_BOUNDARY_MISSING"
    exit 1
}

try {
    $boundary = Get-Content -Raw -Encoding UTF8 -LiteralPath $boundaryPath | ConvertFrom-Json
}
catch {
    Write-Output "status=fail reason_code=SDK_PIPELINE_BOUNDARY_INVALID"
    exit 1
}

if ($boundary.decision_status -ne "TBD-007" -or
    $null -ne $boundary.language_set -or
    $null -ne $boundary.generator -or
    $null -ne $boundary.generator_version -or
    $null -ne $boundary.output_root -or
    $null -ne $boundary.package_registry) {
    Write-Output "status=fail reason_code=SDK_PIPELINE_UNREVIEWED_SELECTION_DETECTED"
    exit 1
}

$output = @(& $openApiCommand sdk-input)
$invocationSucceeded = $?
foreach ($line in $output) {
    Write-Output $line
}
if (-not $invocationSucceeded) {
    exit 1
}

if ($Command -eq "validate") {
    Write-Output "status=pass command=validate reason_code=SDK_PIPELINE_CONTRACT_OK"
    exit 0
}

Write-Output "status=info command=plan reason_code=SDK_GENERATOR_AND_LANGUAGE_TBD detail=TBD-007 requires an explicit language and generator decision before code generation"
Write-Output "status=pass command=plan reason_code=SDK_GENERATION_ENTRYPOINT_OK"
