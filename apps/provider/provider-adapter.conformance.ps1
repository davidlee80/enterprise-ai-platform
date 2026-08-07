[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$contractRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "docs/contracts/providers"

function Read-ContractJson {
    param([string]$Name)
    $path = Join-Path $contractRoot $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "missing Provider contract: $path" }
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

function New-ProviderResult {
    param(
        [object]$Request,
        [object]$Registration,
        [string]$Outcome,
        [string]$ReasonCode,
        [object]$ErrorKind,
        [string]$RetryHint,
        [object]$ResponseMode,
        [object]$Response
    )
    return [PSCustomObject][ordered]@{
        schema_version = 1
        request_id = [string]$Request.request_id
        trace_id = [string]$Request.trace_id
        tenant_id = [string]$Request.tenant_id
        config_version = [int]$Request.config_version
        model_alias = [string]$Request.model_alias
        provider_id = [string]$Request.route.provider_id
        adapter_id = if ($null -eq $Registration) { "unresolved" } else { [string]$Registration.adapter_id }
        adapter_version = if ($null -eq $Registration) { 1 } else { $Registration.adapter_version }
        outcome = $Outcome
        reason_code = $ReasonCode
        error_kind = $ErrorKind
        retry_hint = $RetryHint
        response_mode = $ResponseMode
        response = $Response
    }
}

function Invoke-ReferenceProviderBoundary {
    param(
        [object]$Request,
        [object]$Registry,
        [object]$RuntimeConfig,
        [hashtable]$AdapterImplementations,
        [scriptblock]$SecretResolver
    )

    if ([string]$Request.route.outcome -ne "selected") {
        return New-ProviderResult $Request $null "indeterminate" "ROUTE_NOT_SELECTED" "unavailable" "unknown" $null $null
    }
    if ([string]$Request.tenant_id -ne [string]$Registry.tenant_id -or
        [string]$Request.tenant_id -ne [string]$RuntimeConfig.tenant_id) {
        return New-ProviderResult $Request $null "indeterminate" "PROVIDER_TENANT_MISMATCH" "unavailable" "unknown" $null $null
    }
    if ([int]$Request.config_version -ne [int]$Registry.config_version -or
        [int]$Request.config_version -ne [int]$RuntimeConfig.config_version) {
        return New-ProviderResult $Request $null "indeterminate" "PROVIDER_CONFIG_VERSION_MISMATCH" "unavailable" "unknown" $null $null
    }
    if ([string]$Request.route.provider_id -ne [string]$RuntimeConfig.provider_id) {
        return New-ProviderResult $Request $null "indeterminate" "PROVIDER_BINDING_MISMATCH" "unavailable" "unknown" $null $null
    }

    $registrations = @($Registry.adapters | Where-Object {
        [string]$_.adapter_id -eq [string]$RuntimeConfig.adapter_id -and
        $_.enabled -eq $true -and
        @($_.operations) -contains [string]$Request.operation
    })
    if ($registrations.Count -ne 1 -or -not $AdapterImplementations.ContainsKey([string]$RuntimeConfig.adapter_id)) {
        return New-ProviderResult $Request $null "indeterminate" "PROVIDER_ADAPTER_UNAVAILABLE" "unavailable" "unknown" $null $null
    }
    $registration = $registrations[0]

    try {
        $resolvedCredential = & $SecretResolver ([string]$RuntimeConfig.secret_ref)
    }
    catch {
        return New-ProviderResult $Request $registration "indeterminate" "SECRET_RESOLUTION_FAILED" "unavailable" "unknown" $null $null
    }
    if ([string]::IsNullOrWhiteSpace([string]$resolvedCredential)) {
        return New-ProviderResult $Request $registration "indeterminate" "SECRET_RESOLUTION_FAILED" "unavailable" "unknown" $null $null
    }

    try {
        $adapterResult = & $AdapterImplementations[[string]$RuntimeConfig.adapter_id] $Request $RuntimeConfig $resolvedCredential $registration
    }
    catch {
        return New-ProviderResult $Request $registration "failed" "PROVIDER_CALL_FAILED" "provider_error" "unknown" $null $null
    }
    if ($adapterResult.schema_version -ne 1 -or [string]$adapterResult.reason_code -notmatch '^[A-Z][A-Z0-9_]*$') {
        return New-ProviderResult $Request $registration "failed" "PROVIDER_RESPONSE_INVALID" "invalid_response" "non_retryable" $null $null
    }
    switch ([string]$adapterResult.status) {
        "succeeded" {
            $responseProperty = $adapterResult.PSObject.Properties["response"]
            if ($null -eq $responseProperty) {
                return New-ProviderResult $Request $registration "failed" "PROVIDER_RESPONSE_INVALID" "invalid_response" "non_retryable" $null $null
            }
            $response = Copy-ContractObject $responseProperty.Value
            foreach ($required in @("id", "object", "created", "model", "choices")) {
                if ($null -eq $response.PSObject.Properties[$required]) {
                    return New-ProviderResult $Request $registration "failed" "PROVIDER_RESPONSE_INVALID" "invalid_response" "non_retryable" $null $null
                }
            }
            if (@("chat.completion", "chat.completion.chunk") -notcontains [string]$response.object) {
                return New-ProviderResult $Request $registration "failed" "PROVIDER_RESPONSE_INVALID" "invalid_response" "non_retryable" $null $null
            }
            $response.model = [string]$Request.model_alias
            $mode = if ($Request.stream) { "stream" } else { "complete" }
            return New-ProviderResult $Request $registration "succeeded" "PROVIDER_CALL_SUCCEEDED" $null "not_applicable" $mode $response
        }
        "failed" {
            $allowedKinds = @("authentication", "rate_limit", "timeout", "provider_error", "invalid_response", "unavailable")
            $allowedHints = @("retryable", "non_retryable", "unknown")
            if ($allowedKinds -notcontains [string]$adapterResult.error_kind -or $allowedHints -notcontains [string]$adapterResult.retry_hint) {
                return New-ProviderResult $Request $registration "failed" "PROVIDER_ERROR_CLASSIFICATION_INVALID" "invalid_response" "non_retryable" $null $null
            }
            return New-ProviderResult $Request $registration "failed" ([string]$adapterResult.reason_code) ([string]$adapterResult.error_kind) ([string]$adapterResult.retry_hint) $null $null
        }
        default {
            return New-ProviderResult $Request $registration "indeterminate" "PROVIDER_RUNTIME_UNAVAILABLE" "unavailable" "unknown" $null $null
        }
    }
}

$requestSchema = Read-ContractJson "provider-invocation-request.v1.schema.json"
$resultSchema = Read-ContractJson "provider-invocation-result.v1.schema.json"
$configSchema = Read-ContractJson "provider-runtime-config.v1.schema.json"
$registrySchema = Read-ContractJson "provider-adapter-registry.v1.schema.json"
$boundary = Read-ContractJson "provider-adapter-boundary.v1.json"
$litellmBoundary = Read-ContractJson "litellm-runtime-boundary.v1.json"

foreach ($schema in @($requestSchema, $resultSchema, $configSchema, $registrySchema)) {
    Assert-Condition ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "PROVIDER_SCHEMA_DRAFT_INVALID"
    Assert-Condition ($schema.additionalProperties -eq $false) "PROVIDER_SCHEMA_UNVERSIONED_EXTENSION_ALLOWED"
}
Assert-Condition ($null -eq $boundary.secret_resolver -and $boundary.secret_resolver_status -eq "TBD-012") "PROVIDER_SECRET_MANAGER_PREMATURELY_SELECTED"
Assert-Condition ($boundary.retry_and_fallback.implementation -eq "docs/contracts/retry-fallback/retry-fallback-boundary.v1.json" -and $boundary.retry_and_fallback.status -eq "implemented-v1") "PROVIDER_RETRY_BOUNDARY_MISSING"
Assert-Condition ($null -eq $litellmBoundary.deployment_mode -and $null -eq $litellmBoundary.version) "LITELLM_RUNTIME_TBD_PREMATURELY_SELECTED"
Assert-Condition ($litellmBoundary.retry_fallback_mode -eq "platform_orchestrator" -and $litellmBoundary.retry_fallback_status -eq "implemented-v1") "LITELLM_RETRY_GOVERNANCE_BOUNDARY_INVALID"

$credentialValue = "resolved-" + [Guid]::NewGuid().ToString("N")
$resolver = {
    param($reference)
    if ($reference -ne "secret-ref-test") { throw "unknown test reference" }
    return $credentialValue
}
$failedResolver = { param($reference) throw "test resolver unavailable" }
$script:adapterCalls = 0

$successResponse = [PSCustomObject]@{
    id = "chatcmpl-provider-test"
    object = "chat.completion"
    created = 1767225600
    model = "provider-internal-model"
    choices = @([PSCustomObject]@{ index = 0; message = [PSCustomObject]@{ role = "assistant"; content = "ok" }; finish_reason = "stop" })
}

$implementations = @{
    native_test = {
        param($request, $config, $credential, $registration)
        $script:adapterCalls += 1
        if ($credential -ne $credentialValue) { throw "test credential was not resolved" }
        [PSCustomObject]@{ schema_version = 1; status = "succeeded"; reason_code = "NATIVE_TEST_SUCCEEDED"; response = Copy-ContractObject $successResponse }
    }
    litellm_test = {
        param($request, $config, $credential, $registration)
        $script:adapterCalls += 1
        if ($credential -ne $credentialValue) { throw "test credential was not resolved" }
        [PSCustomObject]@{ schema_version = 1; status = "succeeded"; reason_code = "LITELLM_TEST_SUCCEEDED"; response = Copy-ContractObject $successResponse }
    }
    failure_test = {
        param($request, $config, $credential, $registration)
        $script:adapterCalls += 1
        [PSCustomObject]@{ schema_version = 1; status = "failed"; reason_code = "PROVIDER_TIMEOUT"; error_kind = "timeout"; retry_hint = "retryable" }
    }
    invalid_test = {
        param($request, $config, $credential, $registration)
        $script:adapterCalls += 1
        [PSCustomObject]@{ schema_version = 1; status = "succeeded"; reason_code = "INVALID_TEST_RESPONSE"; response = [PSCustomObject]@{ id = "missing-fields" } }
    }
    throwing_test = {
        param($request, $config, $credential, $registration)
        $script:adapterCalls += 1
        throw "provider-specific test failure must not escape"
    }
}

$baseRequest = [PSCustomObject]@{
    schema_version = 1
    request_id = "request-provider-test"
    trace_id = "trace-provider-test"
    tenant_id = "tenant-verified"
    config_version = 42
    route = [PSCustomObject]@{ outcome = "selected"; provider_id = "provider-a" }
    operation = "chat_completion"
    model_alias = "smart-chat"
    messages = @([PSCustomObject]@{ role = "user"; content = "hello" })
    stream = $false
    obligations = @([PSCustomObject]@{ kind = "disable_body_logging"; enabled = $true })
}
$baseConfig = [PSCustomObject]@{
    schema_version = 1
    tenant_id = "tenant-verified"
    config_version = 42
    provider_id = "provider-a"
    adapter_id = "native_test"
    provider_model = "provider-internal-model"
    endpoint = "endpoint-test-only"
    secret_ref = "secret-ref-test"
}
$baseRegistry = [PSCustomObject]@{
    schema_version = 1
    tenant_id = "tenant-verified"
    config_version = 42
    adapters = @(
        [PSCustomObject]@{ adapter_id = "native_test"; adapter_version = 1; runtime_kind = "native"; operations = @("chat_completion"); enabled = $true },
        [PSCustomObject]@{ adapter_id = "litellm_test"; adapter_version = 1; runtime_kind = "litellm"; operations = @("chat_completion"); enabled = $true },
        [PSCustomObject]@{ adapter_id = "failure_test"; adapter_version = 1; runtime_kind = "native"; operations = @("chat_completion"); enabled = $true },
        [PSCustomObject]@{ adapter_id = "invalid_test"; adapter_version = 1; runtime_kind = "native"; operations = @("chat_completion"); enabled = $true },
        [PSCustomObject]@{ adapter_id = "throwing_test"; adapter_version = 1; runtime_kind = "native"; operations = @("chat_completion"); enabled = $true }
    )
}

$nativeResult = Invoke-ReferenceProviderBoundary (Copy-ContractObject $baseRequest) (Copy-ContractObject $baseRegistry) (Copy-ContractObject $baseConfig) $implementations $resolver
Assert-Condition ($nativeResult.outcome -eq "succeeded" -and $nativeResult.response.model -eq "smart-chat") "PROVIDER_NATIVE_NORMALIZATION_FAILED"
Assert-Condition ($nativeResult.provider_id -eq "provider-a" -and $nativeResult.adapter_id -eq "native_test") "PROVIDER_TRACE_CONTEXT_LOST"

$litellmConfig = Copy-ContractObject $baseConfig
$litellmConfig.adapter_id = "litellm_test"
$litellmResult = Invoke-ReferenceProviderBoundary (Copy-ContractObject $baseRequest) (Copy-ContractObject $baseRegistry) $litellmConfig $implementations $resolver
Assert-Condition ($litellmResult.outcome -eq "succeeded" -and $litellmResult.adapter_id -eq "litellm_test") "LITELLM_ADAPTER_REGISTRATION_FAILED"
Assert-Condition ($litellmResult.response.object -eq "chat.completion") "LITELLM_RESPONSE_NOT_OPENAI_NORMALIZED"

$failureConfig = Copy-ContractObject $baseConfig
$failureConfig.adapter_id = "failure_test"
$script:adapterCalls = 0
$failureResult = Invoke-ReferenceProviderBoundary (Copy-ContractObject $baseRequest) (Copy-ContractObject $baseRegistry) $failureConfig $implementations $resolver
Assert-Condition ($failureResult.outcome -eq "failed" -and $failureResult.reason_code -eq "PROVIDER_TIMEOUT") "PROVIDER_FAILURE_NOT_STRUCTURED"
Assert-Condition ($failureResult.error_kind -eq "timeout" -and $failureResult.retry_hint -eq "retryable") "PROVIDER_FAILURE_CLASSIFICATION_INVALID"
Assert-Condition ($script:adapterCalls -eq 1) "PROVIDER_ADAPTER_PERFORMED_RETRY"

$invalidConfig = Copy-ContractObject $baseConfig
$invalidConfig.adapter_id = "invalid_test"
$invalidResult = Invoke-ReferenceProviderBoundary (Copy-ContractObject $baseRequest) (Copy-ContractObject $baseRegistry) $invalidConfig $implementations $resolver
Assert-Condition ($invalidResult.outcome -eq "failed" -and $invalidResult.reason_code -eq "PROVIDER_RESPONSE_INVALID") "PROVIDER_INVALID_RESPONSE_ACCEPTED"

$throwingConfig = Copy-ContractObject $baseConfig
$throwingConfig.adapter_id = "throwing_test"
$script:adapterCalls = 0
$throwingResult = Invoke-ReferenceProviderBoundary (Copy-ContractObject $baseRequest) (Copy-ContractObject $baseRegistry) $throwingConfig $implementations $resolver
Assert-Condition ($throwingResult.outcome -eq "failed" -and $throwingResult.reason_code -eq "PROVIDER_CALL_FAILED") "PROVIDER_EXCEPTION_NOT_NORMALIZED"
Assert-Condition ($throwingResult.error_kind -eq "provider_error" -and $throwingResult.retry_hint -eq "unknown") "PROVIDER_EXCEPTION_CLASSIFICATION_INVALID"
Assert-Condition ($script:adapterCalls -eq 1) "PROVIDER_EXCEPTION_TRIGGERED_RETRY"

$resolverResult = Invoke-ReferenceProviderBoundary (Copy-ContractObject $baseRequest) (Copy-ContractObject $baseRegistry) (Copy-ContractObject $baseConfig) $implementations $failedResolver
Assert-Condition ($resolverResult.outcome -eq "indeterminate" -and $resolverResult.reason_code -eq "SECRET_RESOLUTION_FAILED") "PROVIDER_SECRET_FAILURE_NOT_STRUCTURED"

foreach ($scenario in @(
    [PSCustomObject]@{ Reason = "ROUTE_NOT_SELECTED"; MutateRequest = { param($r) $r.route.outcome = "no_route" }; MutateRegistry = { param($r) }; MutateConfig = { param($r) } },
    [PSCustomObject]@{ Reason = "PROVIDER_TENANT_MISMATCH"; MutateRequest = { param($r) }; MutateRegistry = { param($r) $r.tenant_id = "tenant-other" }; MutateConfig = { param($r) } },
    [PSCustomObject]@{ Reason = "PROVIDER_CONFIG_VERSION_MISMATCH"; MutateRequest = { param($r) }; MutateRegistry = { param($r) }; MutateConfig = { param($r) $r.config_version = 41 } },
    [PSCustomObject]@{ Reason = "PROVIDER_BINDING_MISMATCH"; MutateRequest = { param($r) }; MutateRegistry = { param($r) }; MutateConfig = { param($r) $r.provider_id = "provider-b" } }
)) {
    $request = Copy-ContractObject $baseRequest
    $registry = Copy-ContractObject $baseRegistry
    $config = Copy-ContractObject $baseConfig
    & $scenario.MutateRequest $request
    & $scenario.MutateRegistry $registry
    & $scenario.MutateConfig $config
    $result = Invoke-ReferenceProviderBoundary $request $registry $config $implementations $resolver
    Assert-Condition ($result.outcome -eq "indeterminate" -and $result.reason_code -eq $scenario.Reason) ("PROVIDER_SCENARIO_FAILED_" + $scenario.Reason)
}

$serialized = @($nativeResult, $litellmResult, $failureResult, $invalidResult, $throwingResult, $resolverResult) | ConvertTo-Json -Depth 20 -Compress
foreach ($forbidden in @($credentialValue, "endpoint-test-only", "secret-ref-test", "provider-internal-model", "raw_error", "stack_trace")) {
    Assert-Condition (-not $serialized.Contains($forbidden)) "PROVIDER_RESULT_SECRET_OR_INTERNAL_DISCLOSURE"
}

Write-Output "status=pass reason_code=PROVIDER_ADAPTER_CONFORMANCE_OK"
