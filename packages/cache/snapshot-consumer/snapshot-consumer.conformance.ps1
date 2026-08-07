[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "SnapshotConsumer.psm1") -Force

function Get-TestHash {
    param([string]$Value)

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
    }
}

function New-TestStoredSnapshot {
    param(
        [string]$TenantId,
        [int]$Version,
        [string[]]$Providers = @("provider-test")
    )

    $json = [ordered]@{
        config_version = $Version
        tenant_id = $TenantId
        model_alias = "smart-chat"
        policy_ids = @("policy-test")
        route_strategy = "priority"
        providers = $Providers
    } | ConvertTo-Json -Compress
    return [PSCustomObject]@{
        tenant_id = $TenantId
        config_version = [string]$Version
        snapshot_json = $json
        content_hash = Get-TestHash $json
        effective_at = "2026-01-01T00:00:00Z"
    }
}

function New-TestNotification {
    param(
        [object]$Stored,
        [string]$Reason = "PUBLISH",
        [string]$Id = ([Guid]::NewGuid().ToString())
    )

    return [PSCustomObject]@{
        schema_version = 1
        notification_id = $Id
        tenant_id = $Stored.tenant_id
        config_version = [int]$Stored.config_version
        content_hash = $Stored.content_hash
        activated_at = "2026-01-01T00:00:01Z"
        transition_reason = $Reason
    }
}

function New-TestCurrentPointer {
    param(
        [object]$Stored,
        [string]$Reason = "PUBLISH"
    )

    return [PSCustomObject]@{
        tenant_id = $Stored.tenant_id
        config_version = $Stored.config_version
        content_hash = $Stored.content_hash
        activated_at = "2026-01-01T00:00:01Z"
        transition_reason = $Reason
    }
}

function Assert-Reason {
    param(
        [object]$Result,
        [bool]$ExpectedOk,
        [string]$ExpectedReason
    )

    if ([bool]$Result.ok -ne $ExpectedOk -or [string]$Result.reason_code -ne $ExpectedReason) {
        throw "Expected ok=$ExpectedOk reason_code=$ExpectedReason; received $($Result | ConvertTo-Json -Compress -Depth 8)"
    }
}

$tenantA = "consumer-tenant-a"
$tenantB = "consumer-tenant-b"
$version1 = New-TestStoredSnapshot $tenantA 1
$version2 = New-TestStoredSnapshot $tenantA 2 @("provider-test", "provider-fallback")
$version3 = New-TestStoredSnapshot $tenantA 3
$store = @{
    "$tenantA|1" = $version1
    "$tenantA|2" = $version2
    "$tenantA|3" = $version3
}
$fetchCount = 0
$fetch = {
    param($TenantId, $ConfigVersion)

    $script:fetchCount += 1
    $key = "$TenantId|$ConfigVersion"
    if (-not $store.ContainsKey($key)) {
        throw "snapshot unavailable"
    }
    return $store[$key]
}.GetNewClosure()
$currentPointers = @{
    $tenantA = New-TestCurrentPointer $version1
}
$readPointer = {
    param($TenantId)

    if (-not $currentPointers.ContainsKey($TenantId)) {
        throw "current pointer unavailable"
    }
    return [PSCustomObject]@{
        ok = $true
        found = $true
        snapshot = $currentPointers[$TenantId]
    }
}.GetNewClosure()

$consumer = New-RuntimeSnapshotConsumer
if ($null -ne $consumer.MaximumStalenessSeconds -or $null -ne $consumer.OnStale) {
    throw "TBD-016/TBD-017 must not receive implicit defaults"
}

$noSnapshot = Get-RuntimeSnapshotLease $consumer $tenantA
Assert-Reason $noSnapshot $false "SNAPSHOT_NOT_LOADED"

$apply1 = Invoke-RuntimeSnapshotNotification $consumer (New-TestNotification $version1) $readPointer $fetch `
    -Now ([DateTimeOffset]::Parse("2026-01-01T00:00:02Z"))
Assert-Reason $apply1 $true "SNAPSHOT_ATOMIC_SWAP_APPLIED"
$inFlightLease = Get-RuntimeSnapshotLease $consumer $tenantA
Assert-Reason $inFlightLease $true "SNAPSHOT_LEASE_CAPTURED"

$currentPointers[$tenantA] = New-TestCurrentPointer $version2
$apply2 = Invoke-RuntimeSnapshotNotification $consumer (New-TestNotification $version2) $readPointer $fetch `
    -Now ([DateTimeOffset]::Parse("2026-01-01T00:00:03Z"))
Assert-Reason $apply2 $true "SNAPSHOT_ATOMIC_SWAP_APPLIED"
$newLease = Get-RuntimeSnapshotLease $consumer $tenantA
if ($inFlightLease.snapshot.config_version -ne "1" -or $newLease.snapshot.config_version -ne "2") {
    throw "Atomic swap did not preserve the old in-flight reference and activate version 2 for new requests"
}

$fetchBeforeDuplicate = $fetchCount
$duplicate = Invoke-RuntimeSnapshotNotification $consumer (New-TestNotification $version2) $readPointer $fetch
Assert-Reason $duplicate $true "SNAPSHOT_NOTIFICATION_DUPLICATE"
if ($fetchCount -ne $fetchBeforeDuplicate) {
    throw "Duplicate notification performed an unnecessary fetch"
}

$stalePublish = Invoke-RuntimeSnapshotNotification $consumer (New-TestNotification $version1) $readPointer $fetch
Assert-Reason $stalePublish $true "SNAPSHOT_NOTIFICATION_STALE"

$orphanNotification = Invoke-RuntimeSnapshotNotification $consumer (New-TestNotification $version3) $readPointer $fetch
Assert-Reason $orphanNotification $false "SNAPSHOT_NOTIFICATION_NOT_CURRENT"

$invalidRollbackOrder = Invoke-RuntimeSnapshotNotification $consumer (New-TestNotification $version3 "ROLLBACK") $readPointer $fetch
Assert-Reason $invalidRollbackOrder $false "SNAPSHOT_ROLLBACK_ORDER_INVALID"

$badHashNotification = New-TestNotification $version3
$badHashNotification.content_hash = ("0" * 64)
$currentPointers[$tenantA] = New-TestCurrentPointer $version3
$currentPointers[$tenantA].content_hash = ("0" * 64)
$hashFailure = Invoke-RuntimeSnapshotNotification $consumer $badHashNotification $readPointer $fetch
Assert-Reason $hashFailure $false "SNAPSHOT_STORED_METADATA_INVALID"
$currentPointers[$tenantA] = New-TestCurrentPointer $version2

$unexpectedField = New-TestNotification $version3
$unexpectedField | Add-Member -NotePropertyName "unversioned_field" -NotePropertyValue "rejected"
$notificationContractFailure = Invoke-RuntimeSnapshotNotification $consumer $unexpectedField $readPointer $fetch
Assert-Reason $notificationContractFailure $false "SNAPSHOT_NOTIFICATION_INVALID"

$sensitiveName = "access_" + "token"
$sensitivePayloadObject = [ordered]@{
    config_version = 5
    tenant_id = $tenantA
    model_alias = "smart-chat"
    policy_ids = @("policy-test")
    route_strategy = "priority"
    providers = @("provider-test")
}
$sensitivePayloadObject[$sensitiveName] = "blocked-value"
$sensitiveJson = $sensitivePayloadObject | ConvertTo-Json -Compress
$sensitiveStored = [PSCustomObject]@{
    tenant_id = $tenantA
    config_version = "5"
    snapshot_json = $sensitiveJson
    content_hash = Get-TestHash $sensitiveJson
    effective_at = "2026-01-01T00:00:00Z"
}
$store["$tenantA|5"] = $sensitiveStored
$currentPointers[$tenantA] = New-TestCurrentPointer $sensitiveStored
$sensitiveFailure = Invoke-RuntimeSnapshotNotification $consumer (New-TestNotification $sensitiveStored) $readPointer $fetch
Assert-Reason $sensitiveFailure $false "SNAPSHOT_PLAINTEXT_CREDENTIAL_FIELD_FORBIDDEN"
$currentPointers[$tenantA] = New-TestCurrentPointer $version2

$duplicateProviderJson = [ordered]@{
    config_version = 6
    tenant_id = $tenantA
    model_alias = "smart-chat"
    policy_ids = @("policy-test")
    route_strategy = "priority"
    providers = @("provider-test", "provider-test")
} | ConvertTo-Json -Compress
$duplicateProviderStored = [PSCustomObject]@{
    tenant_id = $tenantA
    config_version = "6"
    snapshot_json = $duplicateProviderJson
    content_hash = Get-TestHash $duplicateProviderJson
    effective_at = "2026-01-01T00:00:00Z"
}
$store["$tenantA|6"] = $duplicateProviderStored
$currentPointers[$tenantA] = New-TestCurrentPointer $duplicateProviderStored
$coreFailure = Invoke-RuntimeSnapshotNotification $consumer (New-TestNotification $duplicateProviderStored) $readPointer $fetch
Assert-Reason $coreFailure $false "SNAPSHOT_CORE_FIELDS_INVALID"
$currentPointers[$tenantA] = New-TestCurrentPointer $version2

$missingVersion = New-TestStoredSnapshot $tenantA 4
$currentPointers[$tenantA] = New-TestCurrentPointer $missingVersion
$redisOutage = Invoke-RuntimeSnapshotNotification $consumer (New-TestNotification $missingVersion) $readPointer $fetch
Assert-Reason $redisOutage $false "SNAPSHOT_FETCH_FAILED"
$currentPointers[$tenantA] = New-TestCurrentPointer $version2
$afterOutage = Get-RuntimeSnapshotLease $consumer $tenantA
if ($afterOutage.snapshot.config_version -ne "2") {
    throw "Fetch failure cleared or replaced the last validated in-memory Snapshot"
}

$crossTenantStored = New-TestStoredSnapshot $tenantA 1
$crossTenantNotification = New-TestNotification $crossTenantStored
$crossTenantNotification.tenant_id = $tenantB
$currentPointers[$tenantB] = [PSCustomObject]@{
    tenant_id = $tenantB
    config_version = "1"
    content_hash = $crossTenantStored.content_hash
    activated_at = "2026-01-01T00:00:01Z"
    transition_reason = "PUBLISH"
}
$crossTenantFetch = {
    param($TenantId, $ConfigVersion)
    return $crossTenantStored
}.GetNewClosure()
$tenantFailure = Invoke-RuntimeSnapshotNotification $consumer $crossTenantNotification $readPointer $crossTenantFetch
Assert-Reason $tenantFailure $false "SNAPSHOT_STORED_METADATA_INVALID"
$tenantBLease = Get-RuntimeSnapshotLease $consumer $tenantB
Assert-Reason $tenantBLease $false "SNAPSHOT_NOT_LOADED"

$currentPointers[$tenantA] = New-TestCurrentPointer $version1 "ROLLBACK"
$rollback = Invoke-RuntimeSnapshotNotification $consumer (New-TestNotification $version1 "ROLLBACK") $readPointer $fetch `
    -Now ([DateTimeOffset]::Parse("2026-01-01T00:00:04Z"))
Assert-Reason $rollback $true "SNAPSHOT_ATOMIC_SWAP_APPLIED"
$afterRollback = Get-RuntimeSnapshotLease $consumer $tenantA
if ($afterRollback.snapshot.config_version -ne "1") {
    throw "Rollback notification did not activate the retained version"
}

$reconciledConsumer = New-RuntimeSnapshotConsumer
$reconcileReadCurrent = {
    param($TenantId)
    return [PSCustomObject]@{
        ok = $true
        found = $true
        snapshot = [PSCustomObject]@{
            tenant_id = $TenantId
            config_version = "2"
            content_hash = $version2.content_hash
            activated_at = "2026-01-01T00:00:01Z"
            transition_reason = "PUBLISH"
        }
    }
}.GetNewClosure()
$directStoreFetch = {
    param($TenantId, $ConfigVersion)
    return [PSCustomObject]@{
        ok = $true
        found = $true
        snapshot = $store["$TenantId|$ConfigVersion"]
    }
}.GetNewClosure()
$reconcile = Sync-RuntimeSnapshotCurrent $reconciledConsumer $tenantA $reconcileReadCurrent $directStoreFetch `
    -Now ([DateTimeOffset]::Parse("2026-01-01T00:00:03Z"))
Assert-Reason $reconcile $true "SNAPSHOT_ATOMIC_SWAP_APPLIED"
$reconciledLease = Get-RuntimeSnapshotLease $reconciledConsumer $tenantA
if ($reconciledLease.snapshot.config_version -ne "2") {
    throw "Startup/reconnect reconciliation did not activate the current pointer"
}
$failedCurrentRead = {
    param($TenantId)
    throw "Redis unavailable"
}
$reconcileFailure = Sync-RuntimeSnapshotCurrent $reconciledConsumer $tenantA $failedCurrentRead $directStoreFetch
Assert-Reason $reconcileFailure $false "SNAPSHOT_CURRENT_READ_FAILED"
$leaseAfterReconcileFailure = Get-RuntimeSnapshotLease $reconciledConsumer $tenantA
if ($leaseAfterReconcileFailure.snapshot.config_version -ne "2") {
    throw "Current-pointer read failure cleared the last validated Snapshot"
}

$configured = New-RuntimeSnapshotConsumer -MaximumStalenessSeconds 5 -OnStale "fail_closed"
$currentPointers[$tenantA] = New-TestCurrentPointer $version1
$configuredApply = Invoke-RuntimeSnapshotNotification $configured (New-TestNotification $version1) $readPointer $fetch `
    -Now ([DateTimeOffset]::Parse("2026-01-01T00:00:02Z"))
Assert-Reason $configuredApply $true "SNAPSHOT_ATOMIC_SWAP_APPLIED"
$metrics = @(Get-RuntimeSnapshotMetrics $configured -Now ([DateTimeOffset]::Parse("2026-01-01T00:00:10Z")))
if ($metrics.Count -ne 1 -or $metrics[0].active_config_version -ne "1" -or
    $metrics[0].staleness_seconds -ne 10 -or $metrics[0].propagation_latency_seconds -ne 1 -or
    $metrics[0].over_maximum_staleness -ne $true -or $metrics[0].on_stale -ne "fail_closed") {
    throw "Snapshot staleness/config-version telemetry is incomplete"
}
$metricFields = @($metrics[0].PSObject.Properties.Name)
foreach ($forbiddenDimension in @("user_id", "request_id", "notification_id", "content_hash")) {
    if ($metricFields -contains $forbiddenDimension) {
        throw "High-cardinality or sensitive metric dimension is forbidden: $forbiddenDimension"
    }
}

Write-Output "status=pass reason_code=DATA_PLANE_SNAPSHOT_CONSUMER_CONFORMANCE_OK"
