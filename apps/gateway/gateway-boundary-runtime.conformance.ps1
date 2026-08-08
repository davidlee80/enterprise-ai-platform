[CmdletBinding()]
param(
    [ValidateSet("Policy", "Router")]
    [string]$Boundary
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$project = Join-Path $repoRoot "apps/gateway/tests/EnterpriseAiPlatform.Gateway.ArchitectureTests/EnterpriseAiPlatform.Gateway.ArchitectureTests.csproj"

if ($null -eq (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Output "status=fail reason_code=DOTNET_SDK_NOT_AVAILABLE detail=install repository-pinned .NET SDK 10.0.302"
    exit 1
}

$sdkVersion = [string](& dotnet --version)
if ($LASTEXITCODE -ne 0 -or $sdkVersion.Trim() -ne "10.0.302") {
    Write-Output ("status=fail reason_code=DOTNET_SDK_VERSION_MISMATCH expected=10.0.302 actual={0}" -f $sdkVersion.Trim())
    exit 1
}

& dotnet restore $project --locked-mode --nologo
if ($LASTEXITCODE -ne 0) {
    Write-Output "status=fail reason_code=GATEWAY_BOUNDARY_RESTORE_FAILED"
    exit 1
}

$output = @(& dotnet run --project $project --configuration Release --no-restore --nologo)
if ($LASTEXITCODE -ne 0) {
    Write-Output "status=fail reason_code=GATEWAY_BOUNDARY_RUNTIME_FAILED"
    exit 1
}
foreach ($line in $output) { Write-Output $line }

$expected = switch ($Boundary) {
    "Policy" { "status=pass reason_code=POLICY_OPA_RUNTIME_OK*" }
    "Router" { "status=pass reason_code=ROUTER_PLUGIN_RUNTIME_OK*" }
}
if (@($output | Where-Object { $_ -like $expected }).Count -ne 1) {
    Write-Output ("status=fail reason_code={0}_RUNTIME_EVIDENCE_MISSING" -f $Boundary.ToUpperInvariant())
    exit 1
}

Write-Output ("status=pass reason_code={0}_GATEWAY_RUNTIME_CONFORMANCE_OK" -f $Boundary.ToUpperInvariant())
