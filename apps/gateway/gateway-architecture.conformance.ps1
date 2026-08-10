[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$domainProject = "apps/gateway/src/EnterpriseAiPlatform.Gateway.Domain/EnterpriseAiPlatform.Gateway.Domain.csproj"
$applicationProject = "apps/gateway/src/EnterpriseAiPlatform.Gateway.Application/EnterpriseAiPlatform.Gateway.Application.csproj"
$infrastructureProject = "apps/gateway/src/EnterpriseAiPlatform.Gateway.Infrastructure/EnterpriseAiPlatform.Gateway.Infrastructure.csproj"
$hostProject = "apps/gateway/src/EnterpriseAiPlatform.Gateway/EnterpriseAiPlatform.Gateway.csproj"
$testProject = "apps/gateway/tests/EnterpriseAiPlatform.Gateway.ArchitectureTests/EnterpriseAiPlatform.Gateway.ArchitectureTests.csproj"
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

function Get-ProjectDocument {
    param([string]$RelativePath)

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-ConformanceFailure "DDD_PROJECT_MISSING" $RelativePath "required Gateway layer project is absent"
        return $null
    }

    try {
        return [xml](Get-Content -LiteralPath $path -Raw -Encoding UTF8)
    }
    catch {
        Add-ConformanceFailure "DDD_PROJECT_XML_INVALID" $RelativePath $_.Exception.Message
        return $null
    }
}

function Get-ReferenceNames {
    param(
        [xml]$Project,
        [string]$ElementName
    )

    if ($null -eq $Project) {
        return @()
    }

    return @($Project.SelectNodes("//${ElementName}") | ForEach-Object {
        ([string]$_.Include).Replace("\", "/")
    })
}

function Invoke-Dotnet {
    param([string[]]$Arguments)

    $output = @(& dotnet @Arguments)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw ("dotnet command failed with exit code {0}: dotnet {1}" -f $exitCode, ($Arguments -join " "))
    }
    return $output
}

if ($null -eq (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Output "status=fail reason_code=DOTNET_SDK_NOT_AVAILABLE detail=install repository-pinned .NET SDK 10.0.302"
    exit 1
}

$sdkVersion = [string](& dotnet --version)
if ($LASTEXITCODE -ne 0 -or $sdkVersion.Trim() -ne "10.0.302") {
    Write-Output ("status=fail reason_code=DOTNET_SDK_VERSION_MISMATCH expected=10.0.302 actual={0}" -f $sdkVersion.Trim())
    exit 1
}

$domain = Get-ProjectDocument $domainProject
$application = Get-ProjectDocument $applicationProject
$infrastructure = Get-ProjectDocument $infrastructureProject
$hostDocument = Get-ProjectDocument $hostProject
$test = Get-ProjectDocument $testProject

$domainReferences = @(Get-ReferenceNames $domain "ProjectReference")
$domainPackages = @(Get-ReferenceNames $domain "PackageReference")
$domainFrameworks = @(Get-ReferenceNames $domain "FrameworkReference")
if ($domainReferences.Count -ne 0 -or $domainPackages.Count -ne 0 -or $domainFrameworks.Count -ne 0) {
    Add-ConformanceFailure "DDD_DOMAIN_DEPENDENCY_FORBIDDEN" $domainProject "Domain must remain framework-free with no project or package dependencies"
}

$applicationReferences = @(Get-ReferenceNames $application "ProjectReference")
if ($applicationReferences.Count -ne 1 -or
    $applicationReferences[0] -notlike "*EnterpriseAiPlatform.Gateway.Domain.csproj") {
    Add-ConformanceFailure "DDD_APPLICATION_DEPENDENCY_INVALID" $applicationProject "Application may reference Domain only"
}
$applicationPackages = @(Get-ReferenceNames $application "PackageReference")
$applicationFrameworks = @(Get-ReferenceNames $application "FrameworkReference")
if ($applicationPackages.Count -ne 0 -or $applicationFrameworks.Count -ne 0) {
    Add-ConformanceFailure "DDD_APPLICATION_FRAMEWORK_DEPENDENCY_FORBIDDEN" $applicationProject "Application must remain independent of DI and web frameworks"
}

$infrastructureReferences = @(Get-ReferenceNames $infrastructure "ProjectReference")
foreach ($requiredReference in @(
    "EnterpriseAiPlatform.Gateway.Application.csproj",
    "EnterpriseAiPlatform.Gateway.Domain.csproj"
)) {
    if (@($infrastructureReferences | Where-Object { $_ -like "*$requiredReference" }).Count -ne 1) {
        Add-ConformanceFailure "DDD_INFRASTRUCTURE_DEPENDENCY_INVALID" $infrastructureProject "Infrastructure must reference Application and Domain exactly once"
    }
}
if ($infrastructureReferences.Count -ne 2) {
    Add-ConformanceFailure "DDD_INFRASTRUCTURE_DEPENDENCY_INVALID" $infrastructureProject "Infrastructure must not reference Api/Host or unrelated projects"
}
$infrastructurePackages = @(Get-ReferenceNames $infrastructure "PackageReference")
$infrastructureFrameworks = @(Get-ReferenceNames $infrastructure "FrameworkReference")
if ($infrastructurePackages.Count -ne 0 -or
    $infrastructureFrameworks.Count -ne 1 -or
    $infrastructureFrameworks[0] -ne "Microsoft.AspNetCore.App") {
    Add-ConformanceFailure "DI_INFRASTRUCTURE_FRAMEWORK_REFERENCE_INVALID" $infrastructureProject "Infrastructure may use the ADR-002 built-in ASP.NET Core DI framework reference only"
}

$hostReferences = @(Get-ReferenceNames $hostDocument "ProjectReference")
foreach ($requiredReference in @(
    "EnterpriseAiPlatform.Gateway.Application.csproj",
    "EnterpriseAiPlatform.Gateway.Infrastructure.csproj"
)) {
    if (@($hostReferences | Where-Object { $_ -like "*$requiredReference" }).Count -ne 1) {
        Add-ConformanceFailure "DDD_HOST_COMPOSITION_DEPENDENCY_INVALID" $hostProject "Api/Host must reference Application and Infrastructure"
    }
}
if ($hostReferences.Count -ne 2) {
    Add-ConformanceFailure "DDD_HOST_COMPOSITION_DEPENDENCY_INVALID" $hostProject "Api/Host composition dependencies are not minimal"
}
$hostPackages = @(Get-ReferenceNames $hostDocument "PackageReference")
if ($hostPackages.Count -ne 0) {
    Add-ConformanceFailure "DI_THIRD_PARTY_CONTAINER_FORBIDDEN" $hostProject "ADR-002 selects the built-in .NET container without third-party DI packages"
}

$testReferences = @(Get-ReferenceNames $test "ProjectReference")
if ($testReferences.Count -ne 3) {
    Add-ConformanceFailure "DDD_ARCHITECTURE_TEST_DEPENDENCY_INVALID" $testProject "architecture tests must exercise Domain, Application, and Infrastructure"
}
$testPackages = @(Get-ReferenceNames $test "PackageReference")
if ($testPackages.Count -ne 0) {
    Add-ConformanceFailure "DDD_ARCHITECTURE_TEST_PACKAGE_FORBIDDEN" $testProject "architecture conformance must not require third-party test packages"
}

foreach ($relativeRoot in @(
    "apps/gateway/src/EnterpriseAiPlatform.Gateway.Domain",
    "apps/gateway/src/EnterpriseAiPlatform.Gateway.Application"
)) {
    $sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot $relativeRoot) -Recurse -Filter "*.cs" -File | Where-Object {
        $_.FullName -notmatch '[\\/]obj[\\/]|[\\/]bin[\\/]'
    })
    foreach ($sourceFile in $sourceFiles) {
        $content = Get-Content -LiteralPath $sourceFile.FullName -Raw -Encoding UTF8
        if ($content -match "Microsoft\.Extensions\.DependencyInjection|IServiceProvider|GetRequiredService") {
            Add-ConformanceFailure "DDD_INNER_LAYER_SERVICE_LOCATION_FORBIDDEN" $sourceFile.FullName "Domain and Application cannot depend on or resolve the DI container"
        }
    }
}

$registrationFile = "apps/gateway/src/EnterpriseAiPlatform.Gateway.Infrastructure/DependencyInjection.cs"
$programFile = "apps/gateway/src/EnterpriseAiPlatform.Gateway/Program.cs"
$registrationContent = Get-Content -LiteralPath (Join-Path $repoRoot $registrationFile) -Raw -Encoding UTF8
$programContent = Get-Content -LiteralPath (Join-Path $repoRoot $programFile) -Raw -Encoding UTF8
if ($registrationContent -notmatch "TryAddSingleton<IRuntimeReadinessSource,\s*UnavailableRuntimeReadinessSource>") {
    Add-ConformanceFailure "DI_REPLACEABLE_REGISTRATION_MISSING" $registrationFile "Infrastructure must register a replaceable fail-closed Runtime Snapshot port"
}
if ($programContent -notmatch "AddSingleton<GetRuntimeReadiness>" -or
    $programContent -notmatch "AddGatewayInfrastructure" -or
    $programContent -notmatch "ValidateOnBuild\s*=\s*true" -or
    $programContent -notmatch "ValidateScopes\s*=\s*true") {
    Add-ConformanceFailure "DI_COMPOSITION_ROOT_INCOMPLETE" $programFile "Api/Host must be the explicit application and infrastructure composition root"
}

foreach ($projectPath in @($domainProject, $applicationProject, $infrastructureProject, $hostProject, $testProject)) {
    $lockPath = Join-Path (Split-Path (Join-Path $repoRoot $projectPath) -Parent) "packages.lock.json"
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
        Add-ConformanceFailure "DI_PROJECT_LOCK_FILE_MISSING" $projectPath "every restored project requires a committed lock file"
    }
}

if ($failures.Count -eq 0) {
    try {
        Invoke-Dotnet @("restore", (Join-Path $repoRoot $testProject), "--locked-mode", "--nologo") | Out-Null
        $testOutput = @(Invoke-Dotnet @(
            "run",
            "--project",
            (Join-Path $repoRoot $testProject),
            "--configuration",
            "Release",
            "--no-restore",
            "--nologo"
        ))
        if ($testOutput -notcontains "status=pass reason_code=GATEWAY_DDD_DI_RUNTIME_OK container=Microsoft.Extensions.DependencyInjection layers=Domain,Application,Infrastructure,Api") {
            Add-ConformanceFailure "DI_RUNTIME_TEST_EVIDENCE_MISSING" $testProject "container validation and replacement evidence was not emitted"
        }
        if (@($testOutput | Where-Object { $_ -like "status=pass reason_code=GATEWAY_REQUEST_PIPELINE_OK*" }).Count -ne 1) {
            Add-ConformanceFailure "GATEWAY_REQUEST_PIPELINE_EVIDENCE_MISSING" $testProject "authenticated policy/router/provider/fallback/non-blocking Usage evidence was not emitted"
        }
    }
    catch {
        Add-ConformanceFailure "DI_RUNTIME_TEST_FAILED" $testProject $_.Exception.Message
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Output ("status=fail reason_code={0} subject={1} detail={2}" -f $failure.ReasonCode, $failure.Subject, $failure.Detail)
    }
    exit 1
}

Write-Output "status=pass reason_code=GATEWAY_DDD_DI_ARCHITECTURE_OK decision=ADR-002 dependency_graph=Host-to-Application-and-Infrastructure,Infrastructure-to-Application-and-Domain,Application-to-Domain"
