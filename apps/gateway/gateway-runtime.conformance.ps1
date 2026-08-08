[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$projectRelativePath = "apps/gateway/src/EnterpriseAiPlatform.Gateway/EnterpriseAiPlatform.Gateway.csproj"
$projectPath = Join-Path $repoRoot $projectRelativePath
$dllPath = Join-Path $repoRoot "apps/gateway/src/EnterpriseAiPlatform.Gateway/bin/Release/net10.0/EnterpriseAiPlatform.Gateway.dll"
$failures = [System.Collections.Generic.List[object]]::new()
$process = $null
$client = $null

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

function Invoke-Dotnet {
    param([string[]]$Arguments)

    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw ("dotnet command failed with exit code {0}: dotnet {1}" -f $LASTEXITCODE, ($Arguments -join " "))
    }
}

function Read-ResponseBody {
    param([System.Net.Http.HttpResponseMessage]$Response)

    return $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
}

if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
    Write-Output "status=fail reason_code=GATEWAY_PROJECT_MISSING subject=$projectRelativePath"
    exit 1
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

try {
    Invoke-Dotnet @(
        "restore",
        $projectPath,
        "--locked-mode",
        "--nologo"
    )
    Invoke-Dotnet @(
        "build",
        $projectPath,
        "--configuration",
        "Release",
        "--no-restore",
        "--nologo"
    )
}
catch {
    Write-Output ("status=fail reason_code=GATEWAY_DOTNET_BUILD_FAILED detail={0}" -f $_.Exception.Message)
    exit 1
}

if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) {
    Write-Output "status=fail reason_code=GATEWAY_BUILD_ARTIFACT_MISSING subject=$dllPath"
    exit 1
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$listener.Stop()
$baseUri = "http://127.0.0.1:$port"

try {
    $dotnetCommand = Get-Command dotnet -ErrorAction Stop
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $dotnetCommand.Source
    $startInfo.Arguments = '"' + $dllPath + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables["ASPNETCORE_URLS"] = $baseUri
    $startInfo.EnvironmentVariables["DOTNET_ENVIRONMENT"] = "Production"

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Gateway process did not start"
    }

    Add-Type -AssemblyName System.Net.Http
    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromSeconds(3)

    $healthResponse = $null
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(15)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        if ($process.HasExited) {
            throw ("Gateway process exited before health check with code " + $process.ExitCode)
        }

        try {
            $healthResponse = $client.GetAsync("$baseUri/healthz").GetAwaiter().GetResult()
            if ($healthResponse.StatusCode -eq [System.Net.HttpStatusCode]::OK) {
                break
            }
            $healthResponse.Dispose()
            $healthResponse = $null
        }
        catch {
            Start-Sleep -Milliseconds 200
        }
    }

    if ($null -eq $healthResponse) {
        Add-ConformanceFailure "GATEWAY_HEALTH_TIMEOUT" "/healthz" "Gateway did not become live within 15 seconds"
    }
    else {
        $healthBody = Read-ResponseBody $healthResponse
        $health = $healthBody | ConvertFrom-Json
        if ($health.status -ne "live" -or
            $health.service -ne "enterprise-ai-platform-gateway" -or
            [string]::IsNullOrWhiteSpace([string]$health.version)) {
            Add-ConformanceFailure "GATEWAY_HEALTH_RESPONSE_INVALID" "/healthz" "liveness response is missing service, version, or live status"
        }
        $healthResponse.Dispose()
    }

    $readyResponse = $client.GetAsync("$baseUri/readyz").GetAwaiter().GetResult()
    $readyBody = Read-ResponseBody $readyResponse
    $ready = $readyBody | ConvertFrom-Json
    if ([int]$readyResponse.StatusCode -ne 503 -or
        $ready.status -ne "not_ready" -or
        $ready.reason_code -ne "RUNTIME_SNAPSHOT_UNAVAILABLE" -or
        $null -ne $ready.config_version -or
        $null -ne $ready.snapshot_age_seconds) {
        Add-ConformanceFailure "GATEWAY_READINESS_RESPONSE_INVALID" "/readyz" "bootstrap runtime must remain not ready without a validated Runtime Snapshot"
    }
    $readyResponse.Dispose()

    $request = [System.Net.Http.HttpRequestMessage]::new(
        [System.Net.Http.HttpMethod]::Post,
        "$baseUri/v1/chat/completions")
    $null = $request.Headers.TryAddWithoutValidation("Authorization", "Bearer opaque-credential-sentinel")
    $request.Content = [System.Net.Http.StringContent]::new(
        '{"model":"smart-chat","messages":[{"role":"user","content":"prompt-body-sentinel"}]}',
        [System.Text.Encoding]::UTF8,
        "application/json")
    $apiResponse = $client.SendAsync($request).GetAwaiter().GetResult()
    $apiBody = Read-ResponseBody $apiResponse
    if ([int]$apiResponse.StatusCode -ne 503 -or -not [string]::IsNullOrEmpty($apiBody)) {
        Add-ConformanceFailure "GATEWAY_UNCONFIGURED_REQUEST_RESPONSE_INVALID" "/v1/chat/completions" "unconfigured runtime must return 503 without inventing the TBD-008 error body"
    }
    $apiResponse.Dispose()
    $request.Dispose()

    & dotnet $dllPath --health-check "$baseUri/healthz"
    if ($LASTEXITCODE -ne 0) {
        Add-ConformanceFailure "GATEWAY_SELF_HEALTH_PROBE_FAILED" "--health-check" "self-contained container health probe failed"
    }
}
catch {
    Add-ConformanceFailure "GATEWAY_RUNTIME_CONFORMANCE_EXCEPTION" $projectRelativePath $_.Exception.Message
}
finally {
    if ($null -ne $client) {
        $client.Dispose()
    }
    if ($null -ne $process) {
        if (-not $process.HasExited) {
            $process.Kill()
        }
        $process.WaitForExit()
        $standardOutput = $process.StandardOutput.ReadToEnd()
        $standardError = $process.StandardError.ReadToEnd()
        $process.Dispose()

        $combinedOutput = $standardOutput + "`n" + $standardError
        foreach ($forbiddenValue in @("opaque-credential-sentinel", "prompt-body-sentinel")) {
            if ($combinedOutput.IndexOf($forbiddenValue, [StringComparison]::Ordinal) -ge 0) {
                Add-ConformanceFailure "GATEWAY_SENSITIVE_INPUT_LOGGED" $forbiddenValue "credential or request body sentinel appeared in runtime output"
            }
        }
        if ($combinedOutput.IndexOf("RUNTIME_SNAPSHOT_UNAVAILABLE", [StringComparison]::Ordinal) -lt 0) {
            Add-ConformanceFailure "GATEWAY_STRUCTURED_REASON_NOT_LOGGED" "RUNTIME_SNAPSHOT_UNAVAILABLE" "runtime rejection reason code was not emitted"
        }
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Output ("status=fail reason_code={0} subject={1} detail={2}" -f $failure.ReasonCode, $failure.Subject, $failure.Detail)
    }
    exit 1
}

Write-Output "status=pass reason_code=GATEWAY_DOTNET_RUNTIME_CONFORMANCE_OK sdk=10.0.302 framework=net10.0 port=8080 readiness=blocked-until-runtime-snapshot"
