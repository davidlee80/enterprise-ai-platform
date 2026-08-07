[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$contractRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "docs/contracts/router"

function Read-ContractJson {
    param([string]$Name)

    $path = Join-Path $contractRoot $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "missing router contract: $path"
    }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json
}

function Assert-Condition {
    param([bool]$Condition, [string]$ReasonCode)
    if (-not $Condition) { throw $ReasonCode }
}

function Copy-ContractObject {
    param([object]$Value)
    return $Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json
}

function New-RouteDecision {
    param(
        [object]$Request,
        [string]$Outcome,
        [string]$ReasonCode,
        [object]$SelectedProviderId,
        [string[]]$OrderedCandidateIds,
        [object[]]$PluginTrace,
        [string[]]$AppliedObligationKinds,
        [object[]]$ForwardedObligations
    )

    return [PSCustomObject][ordered]@{
        schema_version = 1
        request_id = [string]$Request.request_id
        trace_id = [string]$Request.trace_id
        tenant_id = [string]$Request.tenant_id
        config_version = [int]$Request.config_version
        model_alias = [string]$Request.model_alias
        route_strategy = [string]$Request.route_strategy
        outcome = $Outcome
        reason_code = $ReasonCode
        selected_provider_id = $SelectedProviderId
        ordered_candidate_ids = @($OrderedCandidateIds)
        plugin_trace = @($PluginTrace)
        applied_obligation_kinds = @($AppliedObligationKinds)
        forwarded_obligations = @($ForwardedObligations)
    }
}

function Invoke-ReferenceRouter {
    param(
        [object]$Request,
        [object]$Registry,
        [hashtable]$PluginImplementations
    )

    $trace = @()
    $forwardedObligations = @($Request.policy.obligations | Where-Object { $_.kind -ne "force_region" })
    if ([string]$Request.policy.outcome -ne "allow") {
        return New-RouteDecision $Request "no_route" "POLICY_NOT_ALLOWED" $null @() $trace @() $forwardedObligations
    }
    if ([string]$Request.tenant_id -ne [string]$Registry.tenant_id) {
        return New-RouteDecision $Request "indeterminate" "ROUTER_TENANT_MISMATCH" $null @() $trace @() $forwardedObligations
    }
    if ([int]$Request.config_version -ne [int]$Registry.config_version) {
        return New-RouteDecision $Request "indeterminate" "ROUTER_CONFIG_VERSION_MISMATCH" $null @() $trace @() $forwardedObligations
    }

    $providerIds = @($Request.candidates | ForEach-Object { [string]$_.provider_id })
    if (@($providerIds | Select-Object -Unique).Count -ne $providerIds.Count) {
        return New-RouteDecision $Request "indeterminate" "ROUTER_CANDIDATE_SET_INVALID" $null @() $trace @() $forwardedObligations
    }
    $eligible = @($Request.candidates | Where-Object { $_.enabled -eq $true })
    $forceRegions = @($Request.policy.obligations | Where-Object { $_.kind -eq "force_region" } | ForEach-Object { [string]$_.region } | Select-Object -Unique)
    if ($forceRegions.Count -gt 1) {
        return New-RouteDecision $Request "indeterminate" "ROUTER_OBLIGATION_CONFLICT" $null @() $trace @() $forwardedObligations
    }
    $appliedObligations = @()
    if ($forceRegions.Count -eq 1) {
        $eligible = @($eligible | Where-Object { [string]$_.region -eq $forceRegions[0] })
        $appliedObligations = @("force_region")
    }
    if ($eligible.Count -eq 0) {
        return New-RouteDecision $Request "no_route" "NO_ELIGIBLE_CANDIDATE" $null @() $trace $appliedObligations $forwardedObligations
    }

    $pipelines = @($Registry.pipelines | Where-Object { [string]$_.route_strategy -eq [string]$Request.route_strategy })
    if ($pipelines.Count -eq 0) {
        return New-RouteDecision $Request "no_route" "ROUTE_STRATEGY_NOT_REGISTERED" $null @() $trace $appliedObligations $forwardedObligations
    }
    if ($pipelines.Count -ne 1) {
        return New-RouteDecision $Request "indeterminate" "ROUTER_REGISTRY_INVALID" $null @() $trace $appliedObligations $forwardedObligations
    }

    $orderedIds = @($eligible | ForEach-Object { [string]$_.provider_id })
    foreach ($pluginId in @($pipelines[0].plugin_ids)) {
        $registrations = @($Registry.plugins | Where-Object { [string]$_.plugin_id -eq [string]$pluginId -and $_.enabled -eq $true })
        if ($registrations.Count -ne 1 -or -not $PluginImplementations.ContainsKey([string]$pluginId)) {
            return New-RouteDecision $Request "indeterminate" "ROUTER_PLUGIN_UNAVAILABLE" $null $orderedIds $trace $appliedObligations $forwardedObligations
        }
        $registration = $registrations[0]
        $result = & $PluginImplementations[[string]$pluginId] $Request @($orderedIds) $registration
        if ($result.schema_version -ne 1 -or
            @("applied", "skipped", "rejected", "indeterminate") -notcontains [string]$result.outcome -or
            [string]$result.reason_code -notmatch '^[A-Z][A-Z0-9_]*$') {
            return New-RouteDecision $Request "indeterminate" "ROUTER_PLUGIN_RESULT_INVALID" $null $orderedIds $trace $appliedObligations $forwardedObligations
        }
        $trace += [PSCustomObject][ordered]@{
            plugin_id = [string]$result.plugin_id
            plugin_version = $result.plugin_version
            outcome = [string]$result.outcome
            reason_code = [string]$result.reason_code
        }

        $resultIds = @($result.ordered_candidate_ids | ForEach-Object { [string]$_ })
        $unknownIds = @($resultIds | Where-Object { $orderedIds -notcontains $_ })
        if ([string]$result.plugin_id -ne [string]$registration.plugin_id -or
            [string]$result.plugin_version -ne [string]$registration.plugin_version -or
            @($resultIds | Select-Object -Unique).Count -ne $resultIds.Count -or
            $unknownIds.Count -gt 0) {
            return New-RouteDecision $Request "indeterminate" "ROUTER_PLUGIN_RESULT_INVALID" $null $orderedIds $trace $appliedObligations $forwardedObligations
        }
        switch ([string]$result.outcome) {
            "applied" { $orderedIds = $resultIds }
            "skipped" { }
            "rejected" { return New-RouteDecision $Request "no_route" ([string]$result.reason_code) $null @() $trace $appliedObligations $forwardedObligations }
            default { return New-RouteDecision $Request "indeterminate" ([string]$result.reason_code) $null $orderedIds $trace $appliedObligations $forwardedObligations }
        }
        if ($orderedIds.Count -eq 0) {
            return New-RouteDecision $Request "no_route" "NO_ELIGIBLE_CANDIDATE" $null @() $trace $appliedObligations $forwardedObligations
        }
    }

    return New-RouteDecision $Request "selected" "ROUTE_SELECTED" $orderedIds[0] $orderedIds $trace $appliedObligations $forwardedObligations
}

$requestSchema = Read-ContractJson "router-request.v1.schema.json"
$pluginResultSchema = Read-ContractJson "router-plugin-result.v1.schema.json"
$decisionSchema = Read-ContractJson "route-decision.v1.schema.json"
$registrySchema = Read-ContractJson "router-registry.v1.schema.json"
$boundary = Read-ContractJson "router-boundary.v1.json"

foreach ($schema in @($requestSchema, $pluginResultSchema, $decisionSchema, $registrySchema)) {
    Assert-Condition ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "ROUTER_SCHEMA_DRAFT_INVALID"
    Assert-Condition ($schema.additionalProperties -eq $false) "ROUTER_SCHEMA_UNVERSIONED_EXTENSION_ALLOWED"
}
Assert-Condition ($null -eq $boundary.plugin_method_signature -and $boundary.plugin_method_signature_status -eq "TBD-003") "ROUTER_METHOD_SIGNATURE_PREMATURELY_SELECTED"
Assert-Condition ($null -eq $boundary.selection_algorithm) "ROUTER_ALGORITHM_PREMATURELY_SELECTED"
Assert-Condition ($null -eq $boundary.weight_and_observation_semantics -and $boundary.weight_and_observation_status -eq "TBD-014") "ROUTER_WEIGHT_SEMANTICS_PREMATURELY_SELECTED"

$baseRequest = [PSCustomObject]@{
    schema_version = 1
    request_id = "request-router-test"
    trace_id = "trace-router-test"
    tenant_id = "tenant-verified"
    config_version = 42
    model_alias = "smart-chat"
    route_strategy = "test-composed"
    policy = [PSCustomObject]@{
        outcome = "allow"
        policy_version = 7
        obligations = @([PSCustomObject]@{ kind = "disable_body_logging"; enabled = $true })
    }
    candidates = @(
        [PSCustomObject]@{ provider_id = "provider-a"; region = "cn-north"; priority = 10; weight = 100; enabled = $true },
        [PSCustomObject]@{ provider_id = "provider-b"; region = "cn-south"; priority = 20; weight = 50; enabled = $true }
    )
}

$baseRegistry = [PSCustomObject]@{
    schema_version = 1
    tenant_id = "tenant-verified"
    config_version = 42
    plugins = @([PSCustomObject]@{ plugin_id = "identity"; plugin_version = 1; enabled = $true })
    pipelines = @([PSCustomObject]@{ route_strategy = "test-composed"; plugin_ids = @("identity") })
}

$implementations = @{
    identity = {
        param($request, $candidateIds, $registration)
        [PSCustomObject]@{ schema_version = 1; plugin_id = $registration.plugin_id; plugin_version = $registration.plugin_version; outcome = "applied"; reason_code = "IDENTITY_APPLIED"; ordered_candidate_ids = @($candidateIds) }
    }
    reverse = {
        param($request, $candidateIds, $registration)
        $reversed = @($candidateIds)
        [array]::Reverse($reversed)
        [PSCustomObject]@{ schema_version = 1; plugin_id = $registration.plugin_id; plugin_version = $registration.plugin_version; outcome = "applied"; reason_code = "REVERSE_TEST_APPLIED"; ordered_candidate_ids = $reversed }
    }
    unavailable = {
        param($request, $candidateIds, $registration)
        [PSCustomObject]@{ schema_version = 1; plugin_id = $registration.plugin_id; plugin_version = $registration.plugin_version; outcome = "indeterminate"; reason_code = "PLUGIN_TEST_UNAVAILABLE"; ordered_candidate_ids = @($candidateIds) }
    }
    invalid = {
        param($request, $candidateIds, $registration)
        [PSCustomObject]@{ schema_version = 1; plugin_id = $registration.plugin_id; plugin_version = $registration.plugin_version; outcome = "applied"; reason_code = "INVALID_TEST_RESULT"; ordered_candidate_ids = @("provider-not-in-request") }
    }
}

$baseDecision = Invoke-ReferenceRouter (Copy-ContractObject $baseRequest) (Copy-ContractObject $baseRegistry) $implementations
Assert-Condition ($baseDecision.outcome -eq "selected" -and $baseDecision.selected_provider_id -eq "provider-a") "ROUTER_BASE_PLUGIN_SELECTION_FAILED"

$extendedRegistry = Copy-ContractObject $baseRegistry
$extendedRegistry.plugins += [PSCustomObject]@{ plugin_id = "reverse"; plugin_version = 1; enabled = $true }
$extendedRegistry.pipelines[0].plugin_ids += "reverse"
$extendedDecision = Invoke-ReferenceRouter (Copy-ContractObject $baseRequest) $extendedRegistry $implementations
Assert-Condition ($extendedDecision.outcome -eq "selected" -and $extendedDecision.selected_provider_id -eq "provider-b") "ROUTER_DYNAMIC_PLUGIN_REGISTRATION_FAILED"
Assert-Condition (@($extendedDecision.plugin_trace).Count -eq 2) "ROUTER_PLUGIN_COMPOSITION_TRACE_MISSING"

$obligationRequest = Copy-ContractObject $baseRequest
$obligationRequest.policy.obligations = @(
    [PSCustomObject]@{ kind = "force_region"; region = "cn-north" },
    [PSCustomObject]@{ kind = "disable_body_logging"; enabled = $true }
)
$obligationDecision = Invoke-ReferenceRouter $obligationRequest $extendedRegistry $implementations
Assert-Condition ($obligationDecision.selected_provider_id -eq "provider-a") "ROUTER_FORCE_REGION_NOT_ENFORCED"
Assert-Condition (@($obligationDecision.applied_obligation_kinds) -contains "force_region") "ROUTER_APPLIED_OBLIGATION_NOT_RECORDED"
Assert-Condition (@($obligationDecision.forwarded_obligations.kind) -contains "disable_body_logging") "ROUTER_DOWNSTREAM_OBLIGATION_LOST"

foreach ($scenario in @(
    [PSCustomObject]@{ Reason = "POLICY_NOT_ALLOWED"; Outcome = "no_route"; MutateRequest = { param($r) $r.policy.outcome = "deny" }; MutateRegistry = { param($r) } },
    [PSCustomObject]@{ Reason = "ROUTER_TENANT_MISMATCH"; Outcome = "indeterminate"; MutateRequest = { param($r) }; MutateRegistry = { param($r) $r.tenant_id = "tenant-other" } },
    [PSCustomObject]@{ Reason = "ROUTER_CONFIG_VERSION_MISMATCH"; Outcome = "indeterminate"; MutateRequest = { param($r) }; MutateRegistry = { param($r) $r.config_version = 41 } },
    [PSCustomObject]@{ Reason = "ROUTE_STRATEGY_NOT_REGISTERED"; Outcome = "no_route"; MutateRequest = { param($r) $r.route_strategy = "missing" }; MutateRegistry = { param($r) } }
)) {
    $request = Copy-ContractObject $baseRequest
    $registry = Copy-ContractObject $baseRegistry
    & $scenario.MutateRequest $request
    & $scenario.MutateRegistry $registry
    $decision = Invoke-ReferenceRouter $request $registry $implementations
    Assert-Condition ($decision.outcome -eq $scenario.Outcome -and $decision.reason_code -eq $scenario.Reason) ("ROUTER_SCENARIO_FAILED_" + $scenario.Reason)
}

$unavailableRegistry = Copy-ContractObject $baseRegistry
$unavailableRegistry.plugins[0].plugin_id = "unavailable"
$unavailableRegistry.pipelines[0].plugin_ids = @("unavailable")
$unavailableDecision = Invoke-ReferenceRouter (Copy-ContractObject $baseRequest) $unavailableRegistry $implementations
Assert-Condition ($unavailableDecision.outcome -eq "indeterminate" -and $unavailableDecision.reason_code -eq "PLUGIN_TEST_UNAVAILABLE") "ROUTER_PLUGIN_UNAVAILABLE_NOT_STRUCTURED"

$invalidRegistry = Copy-ContractObject $baseRegistry
$invalidRegistry.plugins[0].plugin_id = "invalid"
$invalidRegistry.pipelines[0].plugin_ids = @("invalid")
$invalidDecision = Invoke-ReferenceRouter (Copy-ContractObject $baseRequest) $invalidRegistry $implementations
Assert-Condition ($invalidDecision.outcome -eq "indeterminate" -and $invalidDecision.reason_code -eq "ROUTER_PLUGIN_RESULT_INVALID") "ROUTER_INVALID_PLUGIN_RESULT_ACCEPTED"

$serialized = @($baseDecision, $extendedDecision, $obligationDecision) | ConvertTo-Json -Depth 20 -Compress
foreach ($forbidden in @("endpoint", "secret_ref", "provider_key", "credential", "litellm")) {
    Assert-Condition (-not $serialized.ToLowerInvariant().Contains($forbidden)) ("ROUTER_DECISION_DISCLOSURE_" + $forbidden.ToUpperInvariant())
}

Write-Output "status=pass reason_code=ROUTER_PLUGIN_CONFORMANCE_OK"
