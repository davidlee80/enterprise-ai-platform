[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("plan")]
    [string]$Command = "plan"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$openApiCommand = Join-Path $repoRoot "scripts/openapi.ps1"

$output = @(& $openApiCommand sdk-input)
$invocationSucceeded = $?
foreach ($line in $output) {
    Write-Output $line
}
if (-not $invocationSucceeded) {
    exit 1
}

Write-Output "status=info command=plan reason_code=SDK_GENERATOR_AND_LANGUAGE_TBD detail=TBD-007 requires an explicit language and generator decision before code generation"
Write-Output "status=pass command=plan reason_code=SDK_GENERATION_ENTRYPOINT_OK"
