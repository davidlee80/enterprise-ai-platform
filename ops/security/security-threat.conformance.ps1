[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$matrix = Get-Content -LiteralPath (Join-Path $PSScriptRoot "threat-control-matrix.v1.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$requiredThreats = @(
    "credential_leakage",
    "cross_tenant_unauthorized_access",
    "malicious_prompt_or_tool_arguments",
    "ssrf_or_data_exfiltration",
    "provider_supply_chain_risk",
    "pii_in_logs",
    "model_output_secret_leakage",
    "replay_attack",
    "resource_exhaustion"
)

foreach ($threat in $requiredThreats) {
    if (@($matrix.threats | Where-Object { $_.threat_id -eq $threat }).Count -ne 1) {
        throw "THREAT_REQUIRED_ENTRY_MISSING: $threat"
    }
}
if ($matrix.production_readiness.all_required_controls_implemented -ne $false -or
    $matrix.production_readiness.missing_control_blocks_promotion -ne $true -or
    $null -ne $matrix.production_readiness.security_approval_ref) {
    throw "THREAT_PRODUCTION_FAIL_CLOSED_INVALID"
}

$gatewaySource = Get-ChildItem -LiteralPath (Join-Path $repoRoot "apps/gateway/src") -Recurse -Filter "*.cs" -File |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }
$gatewayText = $gatewaySource -join "`n"
foreach ($forbiddenDatabaseTerm in @("Npgsql", "DbContext", "control_plane_postgresql")) {
    if ($gatewayText.IndexOf($forbiddenDatabaseTerm, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "THREAT_DATA_PLANE_DATABASE_COUPLING_FOUND: $forbiddenDatabaseTerm"
    }
}

$endpoint = Get-Content -LiteralPath (Join-Path $repoRoot "apps/gateway/src/EnterpriseAiPlatform.Gateway/Api/GatewayEndpoints.cs") -Raw -Encoding UTF8
foreach ($forbiddenLogTemplate in @("authorization={", "request_body={", "response_body={", "prompt={", "messages={")) {
    if ($endpoint.IndexOf($forbiddenLogTemplate, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "THREAT_SENSITIVE_VALUE_LOGGING_FOUND: $forbiddenLogTemplate"
    }
}

$runtimeTests = Get-Content -LiteralPath (Join-Path $repoRoot "apps/gateway/tests/EnterpriseAiPlatform.Gateway.ArchitectureTests/Program.cs") -Raw -Encoding UTF8
foreach ($requiredEvidence in @(
    "POLICY_TENANT_CONTEXT_MISMATCH",
    "GATEWAY_PIPELINE_AUTH_DENIAL_FAILED",
    "GATEWAY_PIPELINE_USAGE_FAILURE_BLOCKED_RESPONSE"
)) {
    if ($runtimeTests.IndexOf($requiredEvidence, [StringComparison]::Ordinal) -lt 0) {
        throw "THREAT_RUNTIME_EVIDENCE_MISSING: $requiredEvidence"
    }
}

Write-Output "status=pass reason_code=THREAT_CONTROL_MATRIX_OK task=TASK-M4-005 threats=9 production_ready=false missing_controls=fail-closed"
