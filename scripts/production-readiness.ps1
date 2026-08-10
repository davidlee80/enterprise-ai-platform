[CmdletBinding()]
param(
    [ValidateSet("evaluate", "self-test")]
    [string]$Mode = "evaluate"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Read-Json {
    param([string]$RelativePath)
    return Get-Content -LiteralPath (Join-Path $repoRoot $RelativePath) -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-ProductionBlockers {
    $blockers = [System.Collections.Generic.List[object]]::new()
    function Add-Blocker([string]$ReasonCode, [string]$Requirement, [string]$Subject) {
        $blockers.Add([PSCustomObject]@{ ReasonCode = $ReasonCode; Requirement = $Requirement; Subject = $Subject })
    }

    $migrationText = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot "packages/db/migrations") -Filter "*.up.sql" -File |
        ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
    foreach ($table in @("user", "role", "api_key", "provider", "provider_capability", "model", "route_policy", "usage", "audit_event")) {
        if ($migrationText -notmatch ("(?im)^CREATE\s+TABLE\s+" + [regex]::Escape($table) + "\s*\(")) {
            Add-Blocker "PRODUCTION_REQUIRED_TABLE_MISSING" "REQ-DB" $table
        }
    }

    $gatewayDefaults = Get-Content -LiteralPath (Join-Path $repoRoot "apps/gateway/src/EnterpriseAiPlatform.Gateway.Infrastructure/Invocation/UnavailableGatewayAdapters.cs") -Raw -Encoding UTF8
    if ($gatewayDefaults.Contains("UnavailableGatewayAuthenticator") -or $gatewayDefaults.Contains("UnavailableGatewayRuntimeSnapshotSource")) {
        Add-Blocker "PRODUCTION_GATEWAY_ADAPTERS_UNCONFIGURED" "REQ-RM-001" "Gateway default adapters"
    }

    $image = Read-Json "deploy/images/gateway/production-image-boundary.v1.json"
    foreach ($field in @("sbom_generator", "image_scanner", "signing_provider")) {
        if ($null -eq $image.supply_chain.$field) {
            Add-Blocker "PRODUCTION_SUPPLY_CHAIN_TOOL_UNCONFIGURED" "REQ-CICD-004" $field
        }
    }

    foreach ($chart in @("control-plane", "runtime", "observability", "dependencies")) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "deploy/helm/$chart") -PathType Container)) {
            Add-Blocker "PRODUCTION_HELM_SCOPE_MISSING" "REQ-HELM-001" $chart
        }
    }
    foreach ($asset in @("deploy/gitops", "deploy/argocd", ".github/workflows/production-promotion.yml")) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $asset))) {
            Add-Blocker "PRODUCTION_GITOPS_ASSET_MISSING" "TASK-M3-004" $asset
        }
    }

    $performance = Read-Json "tests/performance/performance-boundary.v1.json"
    if ($performance.production_readiness.ready -ne $true) {
        Add-Blocker "PRODUCTION_PERFORMANCE_EVIDENCE_MISSING" "TASK-M4-004" "performance production readiness"
    }
    $threat = Read-Json "ops/security/threat-control-matrix.v1.json"
    if ($threat.production_readiness.all_required_controls_implemented -ne $true) {
        Add-Blocker "PRODUCTION_SECURITY_CONTROLS_INCOMPLETE" "TASK-M4-005" "threat controls"
    }
    $capacity = Read-Json "ops/capacity/capacity-boundary.v1.json"
    if ($null -eq $capacity.current_profile_ref -or $null -eq $capacity.current_evidence_ref) {
        Add-Blocker "PRODUCTION_CAPACITY_EVIDENCE_MISSING" "TASK-M5-003" "capacity/N-1 evidence"
    }
    $slo = Read-Json "ops/slo/slo-boundary.v1.json"
    if ($null -eq $slo.target_configuration.active_policy_ref -or $null -eq $slo.data_source.binding_ref) {
        Add-Blocker "PRODUCTION_SLO_BINDING_MISSING" "TASK-M5-001" "SLO policy/data source"
    }
    $ownership = Read-Json "ops/ownership/ownership-catalog.v1.json"
    if (@($ownership.components | Where-Object { $null -eq $_.owner_ref }).Count -gt 0) {
        Add-Blocker "PRODUCTION_OWNER_ASSIGNMENT_MISSING" "REQ-REP-004" "component owners"
    }
    $coordination = Read-Json "ops/coordination/operations-coordination-boundary.v1.json"
    if ($null -eq $coordination.current_on_call_binding.provider_adapter_ref) {
        Add-Blocker "PRODUCTION_ON_CALL_BINDING_MISSING" "REQ-OPS-007" "on-call binding"
    }
    if ($null -eq $coordination.current_approval_binding.approval_system_ref) {
        Add-Blocker "PRODUCTION_APPROVAL_BINDING_MISSING" "REQ-OPS-004" "approval binding"
    }

    return @($blockers)
}

$results = @(Get-ProductionBlockers)
if ($Mode -eq "self-test") {
    foreach ($expected in @(
        "PRODUCTION_REQUIRED_TABLE_MISSING",
        "PRODUCTION_GATEWAY_ADAPTERS_UNCONFIGURED",
        "PRODUCTION_SUPPLY_CHAIN_TOOL_UNCONFIGURED",
        "PRODUCTION_HELM_SCOPE_MISSING",
        "PRODUCTION_GITOPS_ASSET_MISSING",
        "PRODUCTION_PERFORMANCE_EVIDENCE_MISSING",
        "PRODUCTION_SECURITY_CONTROLS_INCOMPLETE",
        "PRODUCTION_CAPACITY_EVIDENCE_MISSING",
        "PRODUCTION_SLO_BINDING_MISSING",
        "PRODUCTION_OWNER_ASSIGNMENT_MISSING",
        "PRODUCTION_ON_CALL_BINDING_MISSING",
        "PRODUCTION_APPROVAL_BINDING_MISSING"
    )) {
        if (@($results | Where-Object { $_.ReasonCode -eq $expected }).Count -eq 0) {
            throw "PRODUCTION_READINESS_EXPECTED_BLOCKER_NOT_DETECTED: $expected"
        }
    }
    Write-Output ("status=pass reason_code=PRODUCTION_READINESS_FAIL_CLOSED_OK blockers={0}" -f $results.Count)
    exit 0
}

if ($results.Count -gt 0) {
    foreach ($blocker in $results) {
        Write-Output ("status=fail command=production-readiness reason_code={0} requirement={1} subject={2}" -f $blocker.ReasonCode, $blocker.Requirement, $blocker.Subject)
    }
    exit 1
}

Write-Output "status=pass command=production-readiness reason_code=PRODUCTION_READINESS_OK"
