[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$contractRoot = Join-Path $repoRoot "docs/contracts/retry-fallback"

function Read-ContractJson {
    param([string]$Name)
    $path = Join-Path $contractRoot $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "missing Retry/Fallback contract: $path" }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json
}

function Assert-Condition {
    param([bool]$Condition, [string]$ReasonCode)
    if (-not $Condition) { throw $ReasonCode }
}

function Copy-ContractObject {
    param([object]$Value)
    return $Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json
}

function New-MockProviderResult {
    param(
        [object]$Invocation,
        [string]$Outcome,
        [string]$ReasonCode,
        [object]$ErrorKind,
        [string]$RetryHint
    )
    $responseMode = $null
    $response = $null
    if ($Outcome -eq "succeeded") {
        $responseMode = if ($Invocation.stream) { "stream" } else { "complete" }
        $response = [PSCustomObject]@{
            id = "chatcmpl-retry-fallback-test"
            object = "chat.completion"
            created = 1767225600
            model = [string]$Invocation.model_alias
            choices = @()
        }
    }
    return [PSCustomObject][ordered]@{
        schema_version = 1
        request_id = [string]$Invocation.request_id
        trace_id = [string]$Invocation.trace_id
        tenant_id = [string]$Invocation.tenant_id
        config_version = [int]$Invocation.config_version
        model_alias = [string]$Invocation.model_alias
        provider_id = [string]$Invocation.route.provider_id
        adapter_id = "failure-injection-adapter"
        adapter_version = 1
        outcome = $Outcome
        reason_code = $ReasonCode
        error_kind = $ErrorKind
        retry_hint = $RetryHint
        response_mode = $responseMode
        response = $response
    }
}

function New-OrchestrationResult {
    param(
        [object]$Request,
        [object]$Plan,
        [array]$Attempts,
        [object]$FinalProviderResult,
        [string]$Outcome,
        [string]$ReasonCode
    )

    $retryCount = @($Attempts | Where-Object { $_.action -eq "retry" }).Count
    $fallbackCount = @($Attempts | Where-Object { $_.action -eq "fallback" }).Count
    $failedProviderIds = @()
    foreach ($attempt in $Attempts) {
        if ($attempt.outcome -ne "succeeded" -and $failedProviderIds -notcontains [string]$attempt.provider_id) {
            $failedProviderIds += [string]$attempt.provider_id
        }
    }
    $finalProviderId = $null
    if ($null -ne $FinalProviderResult) { $finalProviderId = [string]$FinalProviderResult.provider_id }

    $telemetry = [PSCustomObject][ordered]@{
        schema_version = 1
        request_id = [string]$Request.request_id
        trace_id = [string]$Request.trace_id
        tenant_id = [string]$Request.tenant_id
        config_version = [int]$Request.config_version
        model_alias = [string]$Request.model_alias
        plan_id = [string]$Plan.plan_id
        plan_version = $Plan.plan_version
        outcome = $Outcome
        reason_code = $ReasonCode
        initial_provider_id = [string]$Request.invocation.route.provider_id
        final_provider_id = $finalProviderId
        attempt_count = @($Attempts).Count
        retry_count = $retryCount
        fallback_count = $fallbackCount
        fallback_used = ($fallbackCount -gt 0)
        failed_provider_ids = $failedProviderIds
        attempts = @($Attempts)
    }
    return [PSCustomObject][ordered]@{
        schema_version = 1
        request_id = [string]$Request.request_id
        trace_id = [string]$Request.trace_id
        tenant_id = [string]$Request.tenant_id
        config_version = [int]$Request.config_version
        model_alias = [string]$Request.model_alias
        plan_id = [string]$Plan.plan_id
        plan_version = $Plan.plan_version
        outcome = $Outcome
        reason_code = $ReasonCode
        final_provider_result = $FinalProviderResult
        telemetry = $telemetry
    }
}

function Invoke-ReferenceRetryFallback {
    param(
        [object]$Request,
        [object]$Plan,
        [scriptblock]$SingleAttemptInvoker,
        [scriptblock]$DelayRecorder
    )

    $attempts = @()
    if ([string]$Request.tenant_id -ne [string]$Plan.tenant_id -or
        [string]$Request.tenant_id -ne [string]$Request.invocation.tenant_id) {
        return New-OrchestrationResult $Request $Plan $attempts $null "indeterminate" "RETRY_FALLBACK_TENANT_MISMATCH"
    }
    if ([int]$Request.config_version -ne [int]$Plan.config_version -or
        [int]$Request.config_version -ne [int]$Request.invocation.config_version) {
        return New-OrchestrationResult $Request $Plan $attempts $null "indeterminate" "RETRY_FALLBACK_CONFIG_VERSION_MISMATCH"
    }
    if ([string]$Request.request_id -ne [string]$Request.invocation.request_id -or
        [string]$Request.trace_id -ne [string]$Request.invocation.trace_id -or
        [string]$Request.model_alias -ne [string]$Request.invocation.model_alias -or
        [string]$Request.plan_id -ne [string]$Plan.plan_id) {
        return New-OrchestrationResult $Request $Plan $attempts $null "indeterminate" "RETRY_FALLBACK_CONTEXT_MISMATCH"
    }
    if ($Request.invocation.stream -eq $true) {
        return New-OrchestrationResult $Request $Plan $attempts $null "indeterminate" "STREAM_RETRY_POLICY_UNRESOLVED"
    }

    $steps = @($Plan.steps)
    if ($steps.Count -eq 0 -or [int]$Plan.attempt_limit -ne $steps.Count) {
        return New-OrchestrationResult $Request $Plan $attempts $null "indeterminate" "RETRY_FALLBACK_PLAN_INVALID"
    }
    for ($index = 0; $index -lt $steps.Count; $index += 1) {
        $step = $steps[$index]
        if ([int]$step.ordinal -ne ($index + 1) -or @($Request.eligible_provider_ids) -notcontains [string]$step.provider_id) {
            return New-OrchestrationResult $Request $Plan $attempts $null "indeterminate" "RETRY_FALLBACK_PLAN_INVALID"
        }
        if ($index -eq 0) {
            if ([string]$step.action -ne "initial" -or
                [string]$step.provider_id -ne [string]$Request.invocation.route.provider_id -or
                @($step.eligible_error_kinds).Count -ne 0 -or
                [int]$step.delay_ms -ne 0) {
                return New-OrchestrationResult $Request $Plan $attempts $null "indeterminate" "RETRY_FALLBACK_PLAN_INVALID"
            }
        }
        else {
            $previousProviderId = [string]$steps[$index - 1].provider_id
            if (([string]$step.action -eq "retry" -and [string]$step.provider_id -ne $previousProviderId) -or
                ([string]$step.action -eq "fallback" -and [string]$step.provider_id -eq $previousProviderId) -or
                @("retry", "fallback") -notcontains [string]$step.action -or
                @($step.eligible_error_kinds).Count -eq 0) {
                return New-OrchestrationResult $Request $Plan $attempts $null "indeterminate" "RETRY_FALLBACK_PLAN_INVALID"
            }
        }
    }

    $finalProviderResult = $null
    for ($index = 0; $index -lt $steps.Count; $index += 1) {
        $step = $steps[$index]
        if ($index -gt 0) {
            if ([string]$finalProviderResult.retry_hint -ne "retryable" -or
                @($step.eligible_error_kinds) -notcontains [string]$finalProviderResult.error_kind) {
                $reason = if ([string]$finalProviderResult.retry_hint -eq "non_retryable") { "NON_RETRYABLE_PROVIDER_FAILURE" } else { "RETRY_FALLBACK_NOT_ELIGIBLE" }
                return New-OrchestrationResult $Request $Plan $attempts $finalProviderResult ([string]$finalProviderResult.outcome) $reason
            }
            try {
                & $DelayRecorder ([int]$step.delay_ms) ([int]$step.ordinal) ([string]$step.action)
            }
            catch {
                return New-OrchestrationResult $Request $Plan $attempts $finalProviderResult "indeterminate" "RETRY_FALLBACK_DELAY_FAILED"
            }
        }

        $invocation = Copy-ContractObject $Request.invocation
        $invocation.route.provider_id = [string]$step.provider_id
        try {
            $attemptEnvelope = & $SingleAttemptInvoker $invocation
        }
        catch {
            $attempts += [PSCustomObject][ordered]@{
                ordinal = [int]$step.ordinal
                action = [string]$step.action
                provider_id = [string]$step.provider_id
                outcome = "indeterminate"
                reason_code = "PROVIDER_ATTEMPT_INVOCATION_FAILED"
                error_kind = "unavailable"
                retry_hint = "unknown"
                duration_ms = 0
            }
            return New-OrchestrationResult $Request $Plan $attempts $null "indeterminate" "PROVIDER_ATTEMPT_INVOCATION_FAILED"
        }
        if ($null -eq $attemptEnvelope -or
            $null -eq $attemptEnvelope.PSObject.Properties["provider_result"] -or
            $null -eq $attemptEnvelope.PSObject.Properties["duration_ms"] -or
            [int]$attemptEnvelope.duration_ms -lt 0) {
            return New-OrchestrationResult $Request $Plan $attempts $null "indeterminate" "PROVIDER_ATTEMPT_RESULT_INVALID"
        }
        $providerResult = $attemptEnvelope.provider_result
        if ($null -eq $providerResult -or
            [string]$providerResult.request_id -ne [string]$Request.request_id -or
            [string]$providerResult.trace_id -ne [string]$Request.trace_id -or
            [string]$providerResult.tenant_id -ne [string]$Request.tenant_id -or
            [int]$providerResult.config_version -ne [int]$Request.config_version -or
            [string]$providerResult.model_alias -ne [string]$Request.model_alias -or
            [string]$providerResult.provider_id -ne [string]$step.provider_id -or
            @("succeeded", "failed", "indeterminate") -notcontains [string]$providerResult.outcome -or
            [string]$providerResult.reason_code -notmatch '^[A-Z][A-Z0-9_]*$') {
            return New-OrchestrationResult $Request $Plan $attempts $null "indeterminate" "PROVIDER_ATTEMPT_RESULT_INVALID"
        }
        $finalProviderResult = $providerResult
        $attempts += [PSCustomObject][ordered]@{
            ordinal = [int]$step.ordinal
            action = [string]$step.action
            provider_id = [string]$step.provider_id
            outcome = [string]$providerResult.outcome
            reason_code = [string]$providerResult.reason_code
            error_kind = $providerResult.error_kind
            retry_hint = [string]$providerResult.retry_hint
            duration_ms = [int]$attemptEnvelope.duration_ms
        }

        if ([string]$providerResult.outcome -eq "succeeded") {
            $reason = switch ([string]$step.action) {
                "initial" { "PROVIDER_SUCCEEDED" }
                "retry" { "RETRY_SUCCEEDED" }
                "fallback" { "FALLBACK_SUCCEEDED" }
            }
            return New-OrchestrationResult $Request $Plan $attempts $providerResult "succeeded" $reason
        }
        if ([string]$providerResult.retry_hint -ne "retryable") {
            $reason = if ([string]$providerResult.retry_hint -eq "non_retryable") { "NON_RETRYABLE_PROVIDER_FAILURE" } else { "RETRY_FALLBACK_NOT_ELIGIBLE" }
            return New-OrchestrationResult $Request $Plan $attempts $providerResult ([string]$providerResult.outcome) $reason
        }
        if ($index -eq ($steps.Count - 1)) {
            return New-OrchestrationResult $Request $Plan $attempts $providerResult ([string]$providerResult.outcome) "RETRY_FALLBACK_EXHAUSTED"
        }
    }
    return New-OrchestrationResult $Request $Plan $attempts $finalProviderResult "indeterminate" "RETRY_FALLBACK_PLAN_INVALID"
}

$requestSchema = Read-ContractJson "retry-fallback-request.v1.schema.json"
$planSchema = Read-ContractJson "retry-fallback-plan.v1.schema.json"
$resultSchema = Read-ContractJson "retry-fallback-result.v1.schema.json"
$telemetrySchema = Read-ContractJson "retry-fallback-telemetry.v1.schema.json"
$boundary = Read-ContractJson "retry-fallback-boundary.v1.json"
$baseline = Read-ContractJson "retry-fallback-compatibility-baseline.v1.json"

foreach ($schema in @($requestSchema, $planSchema, $resultSchema, $telemetrySchema)) {
    Assert-Condition ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "RETRY_FALLBACK_SCHEMA_DRAFT_INVALID"
    Assert-Condition ($schema.additionalProperties -eq $false) "RETRY_FALLBACK_SCHEMA_UNVERSIONED_EXTENSION_ALLOWED"
}
Assert-Condition ($baseline.request_schema_id -eq $requestSchema.'$id' -and $baseline.plan_schema_id -eq $planSchema.'$id' -and $baseline.result_schema_id -eq $resultSchema.'$id' -and $baseline.telemetry_schema_id -eq $telemetrySchema.'$id') "RETRY_FALLBACK_BASELINE_INVALID"
Assert-Condition ($null -eq $boundary.global_attempt_limit_default) "RETRY_FALLBACK_HIDDEN_ATTEMPT_DEFAULT"
Assert-Condition ($null -eq $boundary.timing_policy.backoff_algorithm -and $null -eq $boundary.timing_policy.jitter_algorithm) "RETRY_FALLBACK_TIMING_PREMATURELY_SELECTED"
Assert-Condition ($null -eq $boundary.public_failure_mapping.mapping -and $boundary.public_failure_mapping.status -eq "TBD-008/TBD-017") "RETRY_FALLBACK_PUBLIC_MAPPING_PREMATURELY_SELECTED"
Assert-Condition (@($boundary.telemetry_projection.forbidden_metric_labels) -contains "request_id" -and @($boundary.telemetry_projection.forbidden_metric_labels) -contains "trace_id" -and @($boundary.telemetry_projection.forbidden_metric_labels) -contains "user_id") "RETRY_FALLBACK_HIGH_CARDINALITY_GUARD_MISSING"

$baseInvocation = [PSCustomObject]@{
    schema_version = 1
    request_id = "request-retry-fallback-test"
    trace_id = "trace-retry-fallback-test"
    tenant_id = "tenant-verified"
    config_version = 42
    route = [PSCustomObject]@{ outcome = "selected"; provider_id = "provider-a" }
    operation = "chat_completion"
    model_alias = "smart-chat"
    messages = @([PSCustomObject]@{ role = "user"; content = "test-only" })
    stream = $false
    obligations = @([PSCustomObject]@{ kind = "disable_body_logging"; enabled = $true })
}
$baseRequest = [PSCustomObject]@{
    schema_version = 1
    request_id = "request-retry-fallback-test"
    trace_id = "trace-retry-fallback-test"
    tenant_id = "tenant-verified"
    config_version = 42
    model_alias = "smart-chat"
    plan_id = "plan-test"
    eligible_provider_ids = @("provider-a", "provider-b")
    invocation = $baseInvocation
}
$basePlan = [PSCustomObject]@{
    schema_version = 1
    tenant_id = "tenant-verified"
    config_version = 42
    plan_id = "plan-test"
    plan_version = 7
    attempt_limit = 3
    steps = @(
        [PSCustomObject]@{ ordinal = 1; action = "initial"; provider_id = "provider-a"; eligible_error_kinds = @(); delay_ms = 0 },
        [PSCustomObject]@{ ordinal = 2; action = "retry"; provider_id = "provider-a"; eligible_error_kinds = @("timeout", "rate_limit", "unavailable"); delay_ms = 10 },
        [PSCustomObject]@{ ordinal = 3; action = "fallback"; provider_id = "provider-b"; eligible_error_kinds = @("timeout", "rate_limit", "provider_error", "unavailable"); delay_ms = 20 }
    )
}

$script:mockSequences = @{}
$script:mockIndexes = @{}
$script:providerCalls = @()
$script:recordedDelays = @()
$invoker = {
    param($invocation)
    $providerId = [string]$invocation.route.provider_id
    $script:providerCalls += $providerId
    $index = 0
    if ($script:mockIndexes.ContainsKey($providerId)) { $index = [int]$script:mockIndexes[$providerId] }
    $sequence = @($script:mockSequences[$providerId])
    if ($index -ge $sequence.Count) { throw "failure injection sequence exhausted" }
    $descriptor = $sequence[$index]
    $script:mockIndexes[$providerId] = $index + 1
    $result = New-MockProviderResult $invocation ([string]$descriptor.outcome) ([string]$descriptor.reason_code) $descriptor.error_kind ([string]$descriptor.retry_hint)
    if ($descriptor.PSObject.Properties["invalid_tenant"]) { $result.tenant_id = "tenant-other" }
    [PSCustomObject]@{ provider_result = $result; duration_ms = [int]$descriptor.duration_ms }
}
$delayRecorder = {
    param($delayMs, $ordinal, $action)
    $script:recordedDelays += [PSCustomObject]@{ delay_ms = $delayMs; ordinal = $ordinal; action = $action }
}

function Set-MockScenario {
    param([hashtable]$Sequences)
    $script:mockSequences = $Sequences
    $script:mockIndexes = @{}
    $script:providerCalls = @()
    $script:recordedDelays = @()
}

$success = [PSCustomObject]@{ outcome = "succeeded"; reason_code = "PROVIDER_CALL_SUCCEEDED"; error_kind = $null; retry_hint = "not_applicable"; duration_ms = 5 }
$timeout = [PSCustomObject]@{ outcome = "failed"; reason_code = "PROVIDER_TIMEOUT"; error_kind = "timeout"; retry_hint = "retryable"; duration_ms = 7 }
$authentication = [PSCustomObject]@{ outcome = "failed"; reason_code = "PROVIDER_AUTHENTICATION_FAILED"; error_kind = "authentication"; retry_hint = "non_retryable"; duration_ms = 3 }
$rateLimit = [PSCustomObject]@{ outcome = "failed"; reason_code = "PROVIDER_RATE_LIMITED"; error_kind = "rate_limit"; retry_hint = "retryable"; duration_ms = 4 }

Set-MockScenario @{ "provider-a" = @($success) }
$initialResult = Invoke-ReferenceRetryFallback (Copy-ContractObject $baseRequest) (Copy-ContractObject $basePlan) $invoker $delayRecorder
Assert-Condition ($initialResult.outcome -eq "succeeded" -and $initialResult.reason_code -eq "PROVIDER_SUCCEEDED") "RETRY_FALLBACK_INITIAL_SUCCESS_FAILED"
Assert-Condition ($initialResult.telemetry.attempt_count -eq 1 -and $initialResult.telemetry.retry_count -eq 0 -and -not $initialResult.telemetry.fallback_used) "RETRY_FALLBACK_INITIAL_TELEMETRY_INVALID"

Set-MockScenario @{ "provider-a" = @($timeout, $timeout); "provider-b" = @($success) }
$fallbackResult = Invoke-ReferenceRetryFallback (Copy-ContractObject $baseRequest) (Copy-ContractObject $basePlan) $invoker $delayRecorder
Assert-Condition ($fallbackResult.outcome -eq "succeeded" -and $fallbackResult.reason_code -eq "FALLBACK_SUCCEEDED") "RETRY_FALLBACK_FAILURE_INJECTION_FAILED"
Assert-Condition (($script:providerCalls -join ",") -eq "provider-a,provider-a,provider-b") "RETRY_FALLBACK_ATTEMPT_ORDER_INVALID"
Assert-Condition (($script:recordedDelays.delay_ms -join ",") -eq "10,20") "RETRY_FALLBACK_EXPLICIT_DELAY_INVALID"
Assert-Condition ($fallbackResult.telemetry.attempt_count -eq 3 -and $fallbackResult.telemetry.retry_count -eq 1 -and $fallbackResult.telemetry.fallback_count -eq 1 -and $fallbackResult.telemetry.fallback_used) "RETRY_FALLBACK_COUNTS_INVALID"
Assert-Condition (($fallbackResult.telemetry.failed_provider_ids -join ",") -eq "provider-a" -and $fallbackResult.telemetry.final_provider_id -eq "provider-b") "RETRY_FALLBACK_PROVIDER_TELEMETRY_INVALID"

Set-MockScenario @{ "provider-a" = @($authentication) }
$nonRetryableResult = Invoke-ReferenceRetryFallback (Copy-ContractObject $baseRequest) (Copy-ContractObject $basePlan) $invoker $delayRecorder
Assert-Condition ($nonRetryableResult.outcome -eq "failed" -and $nonRetryableResult.reason_code -eq "NON_RETRYABLE_PROVIDER_FAILURE") "RETRY_FALLBACK_NON_RETRYABLE_DID_NOT_STOP"
Assert-Condition ($script:providerCalls.Count -eq 1 -and $script:recordedDelays.Count -eq 0) "RETRY_FALLBACK_NON_RETRYABLE_EXTRA_ATTEMPT"

$twoStepPlan = Copy-ContractObject $basePlan
$twoStepPlan.steps = @($twoStepPlan.steps | Select-Object -First 2)
$twoStepPlan.attempt_limit = 2
Set-MockScenario @{ "provider-a" = @($timeout, $timeout) }
$exhaustedResult = Invoke-ReferenceRetryFallback (Copy-ContractObject $baseRequest) $twoStepPlan $invoker $delayRecorder
Assert-Condition ($exhaustedResult.outcome -eq "failed" -and $exhaustedResult.reason_code -eq "RETRY_FALLBACK_EXHAUSTED") "RETRY_FALLBACK_EXHAUSTION_INVALID"

$notEligiblePlan = Copy-ContractObject $basePlan
$notEligiblePlan.steps[1].eligible_error_kinds = @("timeout")
Set-MockScenario @{ "provider-a" = @($rateLimit) }
$notEligibleResult = Invoke-ReferenceRetryFallback (Copy-ContractObject $baseRequest) $notEligiblePlan $invoker $delayRecorder
Assert-Condition ($notEligibleResult.outcome -eq "failed" -and $notEligibleResult.reason_code -eq "RETRY_FALLBACK_NOT_ELIGIBLE") "RETRY_FALLBACK_ERROR_ELIGIBILITY_IGNORED"
Assert-Condition ($script:providerCalls.Count -eq 1) "RETRY_FALLBACK_INELIGIBLE_EXTRA_ATTEMPT"

$tenantPlan = Copy-ContractObject $basePlan
$tenantPlan.tenant_id = "tenant-other"
Set-MockScenario @{}
$tenantResult = Invoke-ReferenceRetryFallback (Copy-ContractObject $baseRequest) $tenantPlan $invoker $delayRecorder
Assert-Condition ($tenantResult.outcome -eq "indeterminate" -and $tenantResult.reason_code -eq "RETRY_FALLBACK_TENANT_MISMATCH" -and $script:providerCalls.Count -eq 0) "RETRY_FALLBACK_TENANT_ISOLATION_FAILED"

$versionPlan = Copy-ContractObject $basePlan
$versionPlan.config_version = 41
Set-MockScenario @{}
$versionResult = Invoke-ReferenceRetryFallback (Copy-ContractObject $baseRequest) $versionPlan $invoker $delayRecorder
Assert-Condition ($versionResult.outcome -eq "indeterminate" -and $versionResult.reason_code -eq "RETRY_FALLBACK_CONFIG_VERSION_MISMATCH" -and $script:providerCalls.Count -eq 0) "RETRY_FALLBACK_CONFIG_VERSION_GUARD_FAILED"

$invalidPlan = Copy-ContractObject $basePlan
$invalidPlan.steps[2].provider_id = "provider-a"
Set-MockScenario @{}
$invalidPlanResult = Invoke-ReferenceRetryFallback (Copy-ContractObject $baseRequest) $invalidPlan $invoker $delayRecorder
Assert-Condition ($invalidPlanResult.outcome -eq "indeterminate" -and $invalidPlanResult.reason_code -eq "RETRY_FALLBACK_PLAN_INVALID" -and $script:providerCalls.Count -eq 0) "RETRY_FALLBACK_PLAN_SEMANTICS_INVALID"

$ineligibleProviderRequest = Copy-ContractObject $baseRequest
$ineligibleProviderRequest.eligible_provider_ids = @("provider-a")
Set-MockScenario @{}
$ineligibleProviderResult = Invoke-ReferenceRetryFallback $ineligibleProviderRequest (Copy-ContractObject $basePlan) $invoker $delayRecorder
Assert-Condition ($ineligibleProviderResult.outcome -eq "indeterminate" -and $ineligibleProviderResult.reason_code -eq "RETRY_FALLBACK_PLAN_INVALID" -and $script:providerCalls.Count -eq 0) "RETRY_FALLBACK_ROUTER_ELIGIBILITY_BYPASSED"

$streamRequest = Copy-ContractObject $baseRequest
$streamRequest.invocation.stream = $true
Set-MockScenario @{}
$streamResult = Invoke-ReferenceRetryFallback $streamRequest (Copy-ContractObject $basePlan) $invoker $delayRecorder
Assert-Condition ($streamResult.outcome -eq "indeterminate" -and $streamResult.reason_code -eq "STREAM_RETRY_POLICY_UNRESOLVED" -and $script:providerCalls.Count -eq 0) "RETRY_FALLBACK_STREAM_POLICY_PREMATURELY_SELECTED"

$invalidContext = Copy-ContractObject $success
$invalidContext | Add-Member -NotePropertyName invalid_tenant -NotePropertyValue $true
Set-MockScenario @{ "provider-a" = @($invalidContext) }
$invalidAttemptResult = Invoke-ReferenceRetryFallback (Copy-ContractObject $baseRequest) (Copy-ContractObject $basePlan) $invoker $delayRecorder
Assert-Condition ($invalidAttemptResult.outcome -eq "indeterminate" -and $invalidAttemptResult.reason_code -eq "PROVIDER_ATTEMPT_RESULT_INVALID") "RETRY_FALLBACK_PROVIDER_RESULT_CONTEXT_ACCEPTED"

$throwingInvoker = { param($invocation) throw "test-only invocation failure" }
Set-MockScenario @{}
$invocationFailureResult = Invoke-ReferenceRetryFallback (Copy-ContractObject $baseRequest) (Copy-ContractObject $basePlan) $throwingInvoker $delayRecorder
Assert-Condition ($invocationFailureResult.outcome -eq "indeterminate" -and $invocationFailureResult.reason_code -eq "PROVIDER_ATTEMPT_INVOCATION_FAILED") "RETRY_FALLBACK_INVOCATION_EXCEPTION_ESCAPED"
Assert-Condition ($invocationFailureResult.telemetry.attempt_count -eq 1 -and ($invocationFailureResult.telemetry.failed_provider_ids -join ",") -eq "provider-a") "RETRY_FALLBACK_INVOCATION_FAILURE_TELEMETRY_INVALID"

$throwingDelay = { param($delayMs, $ordinal, $action) throw "test-only delay failure" }
Set-MockScenario @{ "provider-a" = @($timeout) }
$delayFailureResult = Invoke-ReferenceRetryFallback (Copy-ContractObject $baseRequest) (Copy-ContractObject $basePlan) $invoker $throwingDelay
Assert-Condition ($delayFailureResult.outcome -eq "indeterminate" -and $delayFailureResult.reason_code -eq "RETRY_FALLBACK_DELAY_FAILED") "RETRY_FALLBACK_DELAY_EXCEPTION_ESCAPED"
Assert-Condition ($script:providerCalls.Count -eq 1) "RETRY_FALLBACK_DELAY_FAILURE_EXTRA_ATTEMPT"

$serialized = @($initialResult, $fallbackResult, $nonRetryableResult, $exhaustedResult, $notEligibleResult, $tenantResult, $versionResult, $invalidPlanResult, $ineligibleProviderResult, $streamResult, $invalidAttemptResult, $invocationFailureResult, $delayFailureResult) | ConvertTo-Json -Depth 30 -Compress
foreach ($forbidden in @("endpoint", "secret_ref", "provider_model", "provider_key", "credential", "raw_error", "stack_trace")) {
    Assert-Condition (-not $serialized.Contains($forbidden)) "RETRY_FALLBACK_SECRET_OR_INTERNAL_DISCLOSURE"
}

Write-Output "status=pass reason_code=RETRY_FALLBACK_CONFORMANCE_OK"
