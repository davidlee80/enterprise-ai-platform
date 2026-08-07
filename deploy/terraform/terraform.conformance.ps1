[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$terraformRoot = $PSScriptRoot
$requiredModules = @(
    "network",
    "kubernetes",
    "postgres",
    "redis",
    "kafka",
    "object-storage",
    "kms",
    "dns"
)
$environments = @("dev", "stage", "prod")
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

function Invoke-TerraformSuccess {
    param(
        [string]$Subject,
        [string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = @(& terraform @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($exitCode -ne 0) {
        Add-ConformanceFailure "TERRAFORM_COMMAND_FAILED" $Subject (($output | Out-String).Trim())
    }
}

if ($null -eq (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Output "status=fail reason_code=TERRAFORM_NOT_AVAILABLE detail=install the CI-pinned Terraform version or place a compatible terraform binary on PATH"
    exit 1
}

$terraformVersion = (& terraform version -json 2>&1 | ConvertFrom-Json).terraform_version

foreach ($module in $requiredModules) {
    $modulePath = Join-Path $terraformRoot "modules/$module"
    if (-not (Test-Path -LiteralPath $modulePath -PathType Container)) {
        Add-ConformanceFailure "TERRAFORM_MODULE_MISSING" $module "required module directory is absent"
        continue
    }
    foreach ($file in @("main.tf", "README.md")) {
        if (-not (Test-Path -LiteralPath (Join-Path $modulePath $file) -PathType Leaf)) {
            Add-ConformanceFailure "TERRAFORM_MODULE_FILE_MISSING" "$module/$file" "required module file is absent"
        }
    }
}

foreach ($environment in $environments) {
    $environmentPath = Join-Path $terraformRoot "environments/$environment"
    if (-not (Test-Path -LiteralPath $environmentPath -PathType Container)) {
        Add-ConformanceFailure "TERRAFORM_ENVIRONMENT_MISSING" $environment "required environment root is absent"
        continue
    }
    foreach ($file in @("main.tf", "variables.tf", "outputs.tf", "README.md")) {
        if (-not (Test-Path -LiteralPath (Join-Path $environmentPath $file) -PathType Leaf)) {
            Add-ConformanceFailure "TERRAFORM_ENVIRONMENT_FILE_MISSING" "$environment/$file" "required environment file is absent"
        }
    }
}

$terraformFiles = @(Get-ChildItem -LiteralPath $terraformRoot -Recurse -Filter "*.tf" -File)
foreach ($file in $terraformFiles) {
    $relativePath = $file.FullName.Substring($terraformRoot.Length + 1).Replace("\", "/")
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    if ($content -match '(?m)^\s*provider\s+"' -or $content -match '(?m)^\s*resource\s+"') {
        Add-ConformanceFailure "TERRAFORM_UNAPPROVED_PROVIDER_RESOURCE" $relativePath "provider resources are forbidden before TBD-011 is resolved"
    }
    if ($content -match '(?i)\b(aws|azurerm|google|oci|alicloud|vault)_[a-z0-9_]+\b') {
        Add-ConformanceFailure "TERRAFORM_CLOUD_VENDOR_LEAK" $relativePath "cloud or Secret Manager implementation was selected before ADR approval"
    }
    if ($content -match '(?im)^\s*(password|api_key|provider_key|access_token|private_key)\s*=') {
        Add-ConformanceFailure "TERRAFORM_PLAINTEXT_SECRET_INPUT" $relativePath "credential-shaped Terraform assignment is forbidden"
    }
    if ($content -match '(?m)^\s*backend\s+"') {
        Add-ConformanceFailure "TERRAFORM_BACKEND_SELECTED" $relativePath "remote backend remains a reviewed provider/environment decision"
    }
}

$fixturePath = Join-Path $terraformRoot "tests/valid-configuration.tfvars.json"
if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf)) {
    Add-ConformanceFailure "TERRAFORM_CONFORMANCE_FIXTURE_MISSING" "tests/valid-configuration.tfvars.json" "valid composition fixture is absent"
}
else {
    $fixtureText = Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8
    foreach ($marker in @("fixture", "192.0.2.0/24", "ref://fixture", "fixture.invalid")) {
        if ($fixtureText.IndexOf($marker, [System.StringComparison]::Ordinal) -lt 0) {
            Add-ConformanceFailure "TERRAFORM_FIXTURE_SAFETY_MARKER_MISSING" $marker "fixture must remain visibly non-production"
        }
    }
}

Invoke-TerraformSuccess "fmt-check" @("fmt", "-check", "-recursive", $terraformRoot)

if ($failures.Count -eq 0) {
    $terraformDataSession = [Guid]::NewGuid().ToString("N")
    foreach ($environment in $environments) {
        $environmentPath = Join-Path $terraformRoot "environments/$environment"
        $previousTerraformDataDir = $env:TF_DATA_DIR
        $env:TF_DATA_DIR = Join-Path ([System.IO.Path]::GetTempPath()) ("enterprise-ai-platform-terraform/$terraformDataSession/$environment")
        Invoke-TerraformSuccess "init-$environment" @(
            "-chdir=$environmentPath", "init", "-backend=false", "-input=false", "-no-color"
        )
        Invoke-TerraformSuccess "validate-$environment" @(
            "-chdir=$environmentPath", "validate", "-no-color"
        )
        Invoke-TerraformSuccess "plan-$environment" @(
            "-chdir=$environmentPath", "plan", "-refresh=false", "-lock=false", "-input=false", "-no-color",
            "-var-file=$fixturePath"
        )
        $env:TF_DATA_DIR = $previousTerraformDataDir
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Output ("status=fail reason_code={0} subject={1} detail={2}" -f $failure.ReasonCode, $failure.Subject, $failure.Detail)
    }
    exit 1
}

Write-Output ("status=pass reason_code=TERRAFORM_SKELETON_CONFORMANCE_OK terraform={0} modules=8 environments=dev,stage,prod provider_status=TBD-011 secret_manager_status=TBD-012" -f $terraformVersion)
