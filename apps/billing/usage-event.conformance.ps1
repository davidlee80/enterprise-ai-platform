[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$usageContractRoot = Join-Path $repoRoot "docs/contracts/events/usage"
$eventContractRoot = Join-Path $repoRoot "docs/contracts/events"

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "missing Usage contract: $Path" }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}

function Assert-Condition {
    param([bool]$Condition, [string]$ReasonCode)
    if (-not $Condition) { throw $ReasonCode }
}

function Copy-ContractObject {
    param([object]$Value)
    return $Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json
}

function Test-Uuid {
    param([string]$Value)
    try {
        $null = [Guid]::Parse($Value)
        return $true
    }
    catch { return $false }
}

function New-UsageProcessingResult {
    param(
        [object]$Event,
        [string]$Stage,
        [string]$Outcome,
        [string]$ReasonCode,
        [string]$OnlineResponse,
        [string]$NextAction = "none"
    )
    return [PSCustomObject][ordered]@{
        schema_version = 1
        stage = $Stage
        event_id = [string]$Event.event_id
        usage_record_id = [string]$Event.payload.usage_record_id
        request_id = [string]$Event.request_id
        trace_id = [string]$Event.trace_id
        tenant_id = [string]$Event.tenant_id
        config_version = [int]$Event.payload.config_version
        outcome = $Outcome
        reason_code = $ReasonCode
        online_response = $OnlineResponse
        next_action = $NextAction
    }
}

function New-UsageEvent {
    param(
        [object]$Completion,
        [string]$VerifiedTenantId,
        [string]$EventId,
        [string]$UsageRecordId,
        [string]$StartedAt,
        [string]$CompletedAt
    )

    if (-not (Test-Uuid $VerifiedTenantId) -or -not (Test-Uuid $EventId) -or -not (Test-Uuid $UsageRecordId)) {
        return [PSCustomObject]@{ event = $null; reason_code = "USAGE_EVENT_IDENTIFIER_INVALID" }
    }
    if ([string]$Completion.tenant_id -ne $VerifiedTenantId) {
        return [PSCustomObject]@{ event = $null; reason_code = "USAGE_EVENT_TENANT_MISMATCH" }
    }
    if (@("succeeded", "failed", "indeterminate") -notcontains [string]$Completion.outcome -or
        [string]$Completion.reason_code -notmatch '^[A-Z][A-Z0-9_]*$' -or
        [int]$Completion.config_version -lt 1 -or
        [string]::IsNullOrWhiteSpace([string]$Completion.request_id) -or
        [string]::IsNullOrWhiteSpace([string]$Completion.trace_id) -or
        [string]::IsNullOrWhiteSpace([string]$Completion.model_alias) -or
        [string]::IsNullOrWhiteSpace([string]$Completion.plan_id) -or
        [int]$Completion.retry_count -lt 0 -or [int]$Completion.fallback_count -lt 0 -or
        [bool]$Completion.fallback_used -ne ([int]$Completion.fallback_count -gt 0) -or
        @("not_used", "hit", "miss", "bypassed", "unknown") -notcontains [string]$Completion.cache_status) {
        return [PSCustomObject]@{ event = $null; reason_code = "USAGE_COMPLETION_CONTEXT_INVALID" }
    }
    $tokenUsage = $Completion.token_usage
    if (([string]$tokenUsage.status -eq "reported" -and
            ($null -eq $tokenUsage.input_tokens -or $null -eq $tokenUsage.output_tokens -or $null -eq $tokenUsage.total_tokens -or
             [int]$tokenUsage.input_tokens -lt 0 -or [int]$tokenUsage.output_tokens -lt 0 -or [int]$tokenUsage.total_tokens -lt 0)) -or
        ([string]$tokenUsage.status -eq "unavailable" -and
            ($null -ne $tokenUsage.input_tokens -or $null -ne $tokenUsage.output_tokens -or $null -ne $tokenUsage.total_tokens)) -or
        @("reported", "unavailable") -notcontains [string]$tokenUsage.status) {
        return [PSCustomObject]@{ event = $null; reason_code = "USAGE_TOKEN_OBSERVATION_INVALID" }
    }
    $cost = $Completion.cost
    if (([string]$cost.status -eq "calculated" -and
            ([string]$cost.amount_decimal -notmatch '^[0-9]+(\.[0-9]+)?$' -or
             [string]::IsNullOrWhiteSpace([string]$cost.currency_code) -or
             $null -eq $cost.pricing_version)) -or
        ([string]$cost.status -eq "not_calculated" -and
            ($null -ne $cost.amount_decimal -or $null -ne $cost.currency_code -or $null -ne $cost.pricing_version)) -or
        @("calculated", "not_calculated") -notcontains [string]$cost.status) {
        return [PSCustomObject]@{ event = $null; reason_code = "USAGE_COST_OBSERVATION_INVALID" }
    }
    try {
        $started = [DateTimeOffset]::Parse($StartedAt)
        $completed = [DateTimeOffset]::Parse($CompletedAt)
    }
    catch {
        return [PSCustomObject]@{ event = $null; reason_code = "USAGE_EVENT_TIMESTAMP_INVALID" }
    }
    if ($completed -lt $started) {
        return [PSCustomObject]@{ event = $null; reason_code = "USAGE_EVENT_TIMESTAMP_INVALID" }
    }

    $durationMs = [int][Math]::Round(($completed - $started).TotalMilliseconds)
    $event = [PSCustomObject][ordered]@{
        event_id = $EventId
        event_type = "UsageObserved"
        schema_version = 1
        occurred_at = $CompletedAt
        tenant_id = $VerifiedTenantId
        request_id = [string]$Completion.request_id
        trace_id = [string]$Completion.trace_id
        producer = "gateway-data-plane"
        payload = [PSCustomObject][ordered]@{
            usage_record_id = $UsageRecordId
            request_outcome = [string]$Completion.outcome
            final_reason_code = [string]$Completion.reason_code
            model_alias = [string]$Completion.model_alias
            provider_id = $Completion.provider_id
            config_version = [int]$Completion.config_version
            plan_id = [string]$Completion.plan_id
            plan_version = $Completion.plan_version
            request_started_at = $StartedAt
            request_completed_at = $CompletedAt
            duration_ms = $durationMs
            retry_count = [int]$Completion.retry_count
            fallback_count = [int]$Completion.fallback_count
            fallback_used = [bool]$Completion.fallback_used
            cache_status = [string]$Completion.cache_status
            token_usage = Copy-ContractObject $Completion.token_usage
            cost = Copy-ContractObject $Completion.cost
        }
    }
    return [PSCustomObject]@{ event = $event; reason_code = "USAGE_EVENT_CONSTRUCTED" }
}

function Invoke-UsageEnqueue {
    param([object]$Event, [scriptblock]$TryEnqueue)
    try {
        $accepted = & $TryEnqueue $Event
    }
    catch {
        return New-UsageProcessingResult $Event "enqueue" "rejected" "USAGE_EVENT_ENQUEUE_FAILED" "released"
    }
    if ($accepted -ne $true) {
        return New-UsageProcessingResult $Event "enqueue" "rejected" "USAGE_EVENT_ENQUEUE_REJECTED" "released"
    }
    return New-UsageProcessingResult $Event "enqueue" "accepted" "USAGE_EVENT_ENQUEUED" "released"
}

function Invoke-UsagePublish {
    param([object]$Event, [scriptblock]$Publisher)
    try {
        $published = & $Publisher $Event
    }
    catch {
        return New-UsageProcessingResult $Event "publish" "failed" "USAGE_EVENT_PUBLISH_FAILED" "not_applicable"
    }
    if ($published -ne $true) {
        return New-UsageProcessingResult $Event "publish" "failed" "USAGE_EVENT_PUBLISH_REJECTED" "not_applicable"
    }
    return New-UsageProcessingResult $Event "publish" "published" "USAGE_EVENT_PUBLISHED" "not_applicable"
}

function Invoke-UsageConsume {
    param(
        [object]$Event,
        [hashtable]$SeenEvents,
        [hashtable]$SeenUsageRecords,
        [scriptblock]$Processor = { param($event) return $true },
        [string]$FailureAction = "none"
    )

    if ([string]$Event.event_type -ne "UsageObserved" -or [int]$Event.schema_version -ne 1 -or
        [string]$Event.producer -ne "gateway-data-plane" -or
        [string]::IsNullOrWhiteSpace([string]$Event.request_id) -or
        [string]::IsNullOrWhiteSpace([string]$Event.trace_id) -or
        [int]$Event.payload.config_version -lt 1 -or
        -not (Test-Uuid ([string]$Event.event_id)) -or -not (Test-Uuid ([string]$Event.tenant_id)) -or
        -not (Test-Uuid ([string]$Event.payload.usage_record_id))) {
        return New-UsageProcessingResult $Event "consume" "rejected" "USAGE_EVENT_CONTRACT_INVALID" "not_applicable"
    }
    $eventId = [string]$Event.event_id
    $tenantId = [string]$Event.tenant_id
    $usageKey = $tenantId + "|" + [string]$Event.payload.usage_record_id
    $eventFingerprint = $Event | ConvertTo-Json -Depth 30 -Compress
    $payloadFingerprint = $Event.payload | ConvertTo-Json -Depth 20 -Compress
    if ($SeenEvents.ContainsKey($eventId)) {
        if ([string]$SeenEvents[$eventId].tenant_id -ne $tenantId) {
            return New-UsageProcessingResult $Event "consume" "rejected" "USAGE_EVENT_ID_TENANT_CONFLICT" "not_applicable"
        }
        if ([string]$SeenEvents[$eventId].fingerprint -ne $eventFingerprint) {
            return New-UsageProcessingResult $Event "consume" "rejected" "USAGE_EVENT_ID_CONTENT_CONFLICT" "not_applicable"
        }
        return New-UsageProcessingResult $Event "consume" "duplicate" "USAGE_EVENT_DUPLICATE" "not_applicable"
    }
    if ($SeenUsageRecords.ContainsKey($usageKey)) {
        if ([string]$SeenUsageRecords[$usageKey].payload_fingerprint -ne $payloadFingerprint) {
            return New-UsageProcessingResult $Event "consume" "rejected" "USAGE_RECORD_CONTENT_CONFLICT" "not_applicable"
        }
        $SeenEvents[$eventId] = [PSCustomObject]@{ tenant_id = $tenantId; fingerprint = $eventFingerprint }
        return New-UsageProcessingResult $Event "consume" "duplicate" "USAGE_RECORD_DUPLICATE" "not_applicable"
    }
    try {
        $processed = & $Processor $Event
    }
    catch { $processed = $false }
    if ($processed -ne $true) {
        if (@("retry", "dead_letter") -notcontains $FailureAction) {
            return New-UsageProcessingResult $Event "consume" "failed" "USAGE_CONSUMER_FAILURE_POLICY_UNRESOLVED" "not_applicable"
        }
        return New-UsageProcessingResult $Event "consume" "failed" "USAGE_EVENT_CONSUMER_FAILED" "not_applicable" $FailureAction
    }
    $SeenEvents[$eventId] = [PSCustomObject]@{ tenant_id = $tenantId; fingerprint = $eventFingerprint }
    $SeenUsageRecords[$usageKey] = [PSCustomObject]@{ event_id = $eventId; payload_fingerprint = $payloadFingerprint }
    return New-UsageProcessingResult $Event "consume" "processed" "USAGE_EVENT_PROCESSED" "not_applicable"
}

$envelopeSchema = Read-JsonFile (Join-Path $eventContractRoot "event-envelope.v1.schema.json")
$eventSchema = Read-JsonFile (Join-Path $usageContractRoot "usage-event.v1.schema.json")
$processingSchema = Read-JsonFile (Join-Path $usageContractRoot "usage-processing-result.v1.schema.json")
$boundary = Read-JsonFile (Join-Path $usageContractRoot "usage-event-boundary.v1.json")
$baseline = Read-JsonFile (Join-Path $usageContractRoot "usage-event-compatibility-baseline.v1.json")

Assert-Condition ($envelopeSchema.'$id' -eq "urn:enterprise-ai-platform:event-envelope:v1") "USAGE_EVENT_ENVELOPE_ID_MISSING"
Assert-Condition ($eventSchema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema" -and $processingSchema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "USAGE_EVENT_SCHEMA_DRAFT_INVALID"
Assert-Condition ($processingSchema.additionalProperties -eq $false) "USAGE_PROCESSING_SCHEMA_UNVERSIONED_EXTENSION_ALLOWED"
Assert-Condition ($eventSchema.allOf[0].'$ref' -eq $envelopeSchema.'$id') "USAGE_EVENT_ENVELOPE_BINDING_INVALID"
Assert-Condition ($baseline.event_schema_id -eq $eventSchema.'$id' -and $baseline.processing_result_schema_id -eq $processingSchema.'$id') "USAGE_EVENT_BASELINE_INVALID"
Assert-Condition ($boundary.online_enqueue_mode -eq "non_blocking_try_enqueue") "USAGE_EVENT_ONLINE_MODE_INVALID"
Assert-Condition ($null -eq $boundary.broker_product -and $null -eq $boundary.topic_name -and $null -eq $boundary.partition_key -and $null -eq $boundary.producer_buffer_durability -and $null -eq $boundary.backpressure_overflow_policy -and $null -eq $boundary.publisher_retry_policy -and $null -eq $boundary.dlq_policy) "USAGE_EVENT_TRANSPORT_PREMATURELY_SELECTED"
Assert-Condition ($null -eq $boundary.billing_consumer_store -and $null -eq $boundary.cost_precision_and_currency_policy) "USAGE_EVENT_STORAGE_OR_COST_PREMATURELY_SELECTED"

$tenantA = "10000000-0000-0000-0000-000000000001"
$tenantB = "10000000-0000-0000-0000-000000000002"
$eventId = "20000000-0000-0000-0000-000000000001"
$usageRecordId = "30000000-0000-0000-0000-000000000001"
$script:stageLog = @()
$script:queue = @()

$authenticationDecision = [PSCustomObject]@{ outcome = "authenticated"; tenant_id = $tenantA }
$policyDecision = [PSCustomObject]@{ outcome = "allow"; tenant_id = $tenantA; config_version = 42 }
$routeDecision = [PSCustomObject]@{ outcome = "selected"; tenant_id = $tenantA; config_version = 42; provider_id = "provider-b" }
Assert-Condition ($authenticationDecision.outcome -eq "authenticated") "USAGE_E2E_AUTHENTICATION_FAILED"
$script:stageLog += "authenticated"
Assert-Condition ($policyDecision.outcome -eq "allow" -and $policyDecision.tenant_id -eq $authenticationDecision.tenant_id) "USAGE_E2E_POLICY_FAILED"
$script:stageLog += "policy_allowed"
Assert-Condition ($routeDecision.outcome -eq "selected" -and $routeDecision.tenant_id -eq $policyDecision.tenant_id -and $routeDecision.config_version -eq $policyDecision.config_version) "USAGE_E2E_ROUTER_FAILED"
$script:stageLog += "route_selected"

$script:providerMockCalls = 0
$providerMock = {
    $script:providerMockCalls += 1
    [PSCustomObject]@{
        outcome = "succeeded"
        reason_code = "FALLBACK_SUCCEEDED"
        request_id = "request-usage-e2e"
        trace_id = "trace-usage-e2e"
        tenant_id = $tenantA
        config_version = 42
        model_alias = "smart-chat"
        provider_id = "provider-b"
        plan_id = "plan-test"
        plan_version = 7
        retry_count = 1
        fallback_count = 1
        fallback_used = $true
        cache_status = "not_used"
        token_usage = [PSCustomObject]@{ status = "reported"; input_tokens = 12; output_tokens = 8; total_tokens = 20 }
        cost = [PSCustomObject]@{ status = "not_calculated"; amount_decimal = $null; currency_code = $null; pricing_version = $null }
    }
}
$completion = & $providerMock
Assert-Condition ($script:providerMockCalls -eq 1 -and $completion.provider_id -eq $routeDecision.provider_id) "USAGE_E2E_PROVIDER_MOCK_FAILED"
$script:stageLog += "provider_mock_completed"

$composition = New-UsageEvent $completion $tenantA $eventId $usageRecordId "2026-08-07T00:00:00Z" "2026-08-07T00:00:01Z"
Assert-Condition ($composition.reason_code -eq "USAGE_EVENT_CONSTRUCTED" -and $null -ne $composition.event) "USAGE_EVENT_COMPOSITION_FAILED"
$usageEvent = $composition.event
$script:stageLog += "usage_event_constructed"

$tryEnqueue = {
    param($event)
    $script:queue += Copy-ContractObject $event
    $script:stageLog += "usage_enqueued"
    return $true
}
$enqueueResult = Invoke-UsageEnqueue $usageEvent $tryEnqueue
Assert-Condition ($enqueueResult.outcome -eq "accepted" -and $enqueueResult.online_response -eq "released") "USAGE_EVENT_ENQUEUE_DID_NOT_RELEASE_RESPONSE"
$script:stageLog += "response_released"
Assert-Condition ($script:queue.Count -eq 1 -and $script:providerMockCalls -eq 1) "USAGE_EVENT_ENQUEUE_MUTATED_ONLINE_RESULT"

$publisher = {
    param($event)
    $script:stageLog += "usage_published"
    return $true
}
$publishResult = Invoke-UsagePublish $script:queue[0] $publisher
Assert-Condition ($publishResult.outcome -eq "published") "USAGE_EVENT_ASYNC_PUBLISH_FAILED"
$releaseIndex = [Array]::IndexOf($script:stageLog, "response_released")
$publishIndex = [Array]::IndexOf($script:stageLog, "usage_published")
Assert-Condition ($releaseIndex -ge 0 -and $publishIndex -gt $releaseIndex) "USAGE_EVENT_PUBLISH_BLOCKED_ONLINE_RESPONSE"

$seenEvents = @{}
$seenUsageRecords = @{}
$consumeResult = Invoke-UsageConsume $script:queue[0] $seenEvents $seenUsageRecords
Assert-Condition ($consumeResult.outcome -eq "processed" -and $consumeResult.reason_code -eq "USAGE_EVENT_PROCESSED") "USAGE_EVENT_CONSUMER_FAILED"
$duplicateEventResult = Invoke-UsageConsume (Copy-ContractObject $script:queue[0]) $seenEvents $seenUsageRecords
Assert-Condition ($duplicateEventResult.outcome -eq "duplicate" -and $duplicateEventResult.reason_code -eq "USAGE_EVENT_DUPLICATE") "USAGE_EVENT_IDEMPOTENCY_FAILED"

$eventContentConflict = Copy-ContractObject $script:queue[0]
$eventContentConflict.payload.token_usage.total_tokens = 21
$eventContentConflictResult = Invoke-UsageConsume $eventContentConflict $seenEvents $seenUsageRecords
Assert-Condition ($eventContentConflictResult.outcome -eq "rejected" -and $eventContentConflictResult.reason_code -eq "USAGE_EVENT_ID_CONTENT_CONFLICT") "USAGE_EVENT_IDEMPOTENCY_CONFLICT_ACCEPTED"

$businessDuplicate = Copy-ContractObject $script:queue[0]
$businessDuplicate.event_id = "20000000-0000-0000-0000-000000000002"
$businessDuplicateResult = Invoke-UsageConsume $businessDuplicate $seenEvents $seenUsageRecords
Assert-Condition ($businessDuplicateResult.outcome -eq "duplicate" -and $businessDuplicateResult.reason_code -eq "USAGE_RECORD_DUPLICATE") "USAGE_BUSINESS_IDEMPOTENCY_FAILED"

$businessConflict = Copy-ContractObject $script:queue[0]
$businessConflict.event_id = "20000000-0000-0000-0000-000000000005"
$businessConflict.payload.token_usage.total_tokens = 21
$businessConflictResult = Invoke-UsageConsume $businessConflict $seenEvents $seenUsageRecords
Assert-Condition ($businessConflictResult.outcome -eq "rejected" -and $businessConflictResult.reason_code -eq "USAGE_RECORD_CONTENT_CONFLICT") "USAGE_BUSINESS_IDEMPOTENCY_CONFLICT_ACCEPTED"

$tenantBEvent = Copy-ContractObject $script:queue[0]
$tenantBEvent.event_id = "20000000-0000-0000-0000-000000000003"
$tenantBEvent.tenant_id = $tenantB
$tenantBResult = Invoke-UsageConsume $tenantBEvent $seenEvents $seenUsageRecords
Assert-Condition ($tenantBResult.outcome -eq "processed") "USAGE_TENANT_SCOPED_IDEMPOTENCY_FAILED"

$tenantConflict = Copy-ContractObject $script:queue[0]
$tenantConflict.tenant_id = $tenantB
$tenantConflictResult = Invoke-UsageConsume $tenantConflict $seenEvents $seenUsageRecords
Assert-Condition ($tenantConflictResult.outcome -eq "rejected" -and $tenantConflictResult.reason_code -eq "USAGE_EVENT_ID_TENANT_CONFLICT") "USAGE_EVENT_TENANT_CONFLICT_ACCEPTED"

$rejectQueue = { param($event) return $false }
$enqueueRejected = Invoke-UsageEnqueue $usageEvent $rejectQueue
Assert-Condition ($enqueueRejected.outcome -eq "rejected" -and $enqueueRejected.reason_code -eq "USAGE_EVENT_ENQUEUE_REJECTED" -and $enqueueRejected.online_response -eq "released") "USAGE_EVENT_BACKPRESSURE_BLOCKED_RESPONSE"

$failedPublisher = { param($event) throw "test-only broker failure" }
$publishFailed = Invoke-UsagePublish $usageEvent $failedPublisher
Assert-Condition ($publishFailed.outcome -eq "failed" -and $publishFailed.reason_code -eq "USAGE_EVENT_PUBLISH_FAILED" -and $enqueueResult.online_response -eq "released") "USAGE_EVENT_PUBLISH_FAILURE_CHANGED_RESPONSE"

$failedProcessor = { param($event) throw "test-only consumer failure" }
$retrySeenEvents = @{}
$retrySeenUsage = @{}
$consumerRetry = Invoke-UsageConsume (Copy-ContractObject $usageEvent) $retrySeenEvents $retrySeenUsage $failedProcessor "retry"
Assert-Condition ($consumerRetry.outcome -eq "failed" -and $consumerRetry.next_action -eq "retry" -and $retrySeenEvents.Count -eq 0 -and $retrySeenUsage.Count -eq 0) "USAGE_CONSUMER_RETRY_CONTRACT_FAILED"
$dlqSeenEvents = @{}
$dlqSeenUsage = @{}
$consumerDlq = Invoke-UsageConsume (Copy-ContractObject $usageEvent) $dlqSeenEvents $dlqSeenUsage $failedProcessor "dead_letter"
Assert-Condition ($consumerDlq.outcome -eq "failed" -and $consumerDlq.next_action -eq "dead_letter" -and $dlqSeenEvents.Count -eq 0 -and $dlqSeenUsage.Count -eq 0) "USAGE_CONSUMER_DLQ_CONTRACT_FAILED"
$unresolvedConsumerFailure = Invoke-UsageConsume (Copy-ContractObject $usageEvent) @{} @{} $failedProcessor
Assert-Condition ($unresolvedConsumerFailure.outcome -eq "failed" -and $unresolvedConsumerFailure.reason_code -eq "USAGE_CONSUMER_FAILURE_POLICY_UNRESOLVED" -and $unresolvedConsumerFailure.next_action -eq "none") "USAGE_CONSUMER_POLICY_PREMATURELY_SELECTED"

$tenantMismatchCompletion = Copy-ContractObject $completion
$tenantMismatchCompletion.tenant_id = $tenantB
$tenantMismatchComposition = New-UsageEvent $tenantMismatchCompletion $tenantA "20000000-0000-0000-0000-000000000004" "30000000-0000-0000-0000-000000000004" "2026-08-07T00:00:00Z" "2026-08-07T00:00:01Z"
Assert-Condition ($tenantMismatchComposition.reason_code -eq "USAGE_EVENT_TENANT_MISMATCH" -and $null -eq $tenantMismatchComposition.event) "USAGE_EVENT_TENANT_MISMATCH_ACCEPTED"

$failedCompletion = Copy-ContractObject $completion
$failedCompletion.outcome = "failed"
$failedCompletion.reason_code = "RETRY_FALLBACK_EXHAUSTED"
$failedCompletion.token_usage = [PSCustomObject]@{ status = "unavailable"; input_tokens = $null; output_tokens = $null; total_tokens = $null }
$failedComposition = New-UsageEvent $failedCompletion $tenantA "20000000-0000-0000-0000-000000000006" "30000000-0000-0000-0000-000000000006" "2026-08-07T00:00:00Z" "2026-08-07T00:00:02Z"
Assert-Condition ($failedComposition.reason_code -eq "USAGE_EVENT_CONSTRUCTED" -and $failedComposition.event.payload.request_outcome -eq "failed" -and $failedComposition.event.payload.token_usage.status -eq "unavailable") "USAGE_FAILED_REQUEST_EVENT_INVALID"

$serializedEvent = $usageEvent | ConvertTo-Json -Depth 30 -Compress
$serializedResults = @($enqueueResult, $publishResult, $consumeResult, $duplicateEventResult, $eventContentConflictResult, $businessDuplicateResult, $businessConflictResult, $tenantBResult, $tenantConflictResult, $enqueueRejected, $publishFailed, $consumerRetry, $consumerDlq, $unresolvedConsumerFailure) | ConvertTo-Json -Depth 20 -Compress
foreach ($forbidden in @("endpoint", "secret_ref", "provider_model", "provider_key", "credential", "prompt", "messages", "response_body", "raw_error", "stack_trace")) {
    Assert-Condition (-not $serializedEvent.Contains($forbidden) -and -not $serializedResults.Contains($forbidden)) "USAGE_EVENT_SECRET_BODY_OR_INTERNAL_DISCLOSURE"
}

Write-Output "status=pass reason_code=USAGE_EVENT_CONFORMANCE_OK"
