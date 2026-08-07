[CmdletBinding()]
param(
    [string]$RedisHost = "127.0.0.1",
    [int]$RedisPort = 6379,
    [switch]$UseDocker,
    [string]$RedisImage = "redis:8.8.1-trixie"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path

function Get-ContentHash {
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

function Get-ScriptPath {
    param([string]$Name)

    if ($UseDocker) {
        return "/workspace/packages/cache/snapshot-store/$Name"
    }
    return (Join-Path $PSScriptRoot $Name)
}

function Invoke-RedisClient {
    param([string[]]$ClientArguments)

    if ($UseDocker) {
        $mount = "${repoRoot}:/workspace:ro"
        $output = @(& docker run --rm --network host --volume $mount $RedisImage redis-cli `
            -h $RedisHost -p $RedisPort --raw @ClientArguments 2>&1)
    }
    else {
        $output = @(& redis-cli -h $RedisHost -p $RedisPort --raw @ClientArguments 2>&1)
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Redis client failed: $($output -join ' ')"
    }
    return $output
}

function Invoke-SnapshotScript {
    param(
        [string]$Script,
        [string[]]$Keys,
        [string[]]$Arguments
    )

    $clientArguments = @("--eval", (Get-ScriptPath $Script)) + $Keys + @(",") + $Arguments
    $raw = (Invoke-RedisClient $clientArguments) -join "`n"
    try {
        return $raw | ConvertFrom-Json
    }
    catch {
        throw "Snapshot script returned non-JSON output: $raw"
    }
}

function Assert-Reason {
    param(
        [object]$Result,
        [bool]$ExpectedOk,
        [string]$ExpectedReason
    )

    if ([bool]$Result.ok -ne $ExpectedOk -or [string]$Result.reason_code -ne $ExpectedReason) {
        throw "Expected ok=$ExpectedOk reason_code=$ExpectedReason; received $($Result | ConvertTo-Json -Compress)"
    }
}

$tenantA = "m1003-$([Guid]::NewGuid().ToString('N'))"
$tenantB = "m1003-$([Guid]::NewGuid().ToString('N'))"
$currentA = "runtime-snapshot:{$tenantA}:current"
$versionA1 = "runtime-snapshot:{$tenantA}:version:1"
$versionA2 = "runtime-snapshot:{$tenantA}:version:2"
$notificationsA = "runtime-snapshot:{$tenantA}:notifications"
$effectiveAt = "2026-01-01T00:00:00Z"
$activatedAt = [DateTimeOffset]::UtcNow.ToString("o")
$notification1 = [Guid]::NewGuid().ToString()
$notification2 = [Guid]::NewGuid().ToString()

$snapshot1 = [ordered]@{
    config_version = 1
    tenant_id = $tenantA
    model_alias = "smart-chat"
    policy_ids = @("p_budget", "p_region")
    route_strategy = "latency_cost_weighted"
    providers = @("provider-us", "provider-jp")
} | ConvertTo-Json -Compress
$snapshot2 = [ordered]@{
    config_version = 2
    tenant_id = $tenantA
    model_alias = "smart-chat"
    policy_ids = @("p_budget", "p_region")
    route_strategy = "latency_cost_weighted"
    providers = @("provider-ap")
} | ConvertTo-Json -Compress

$publish1 = Invoke-SnapshotScript "publish.lua" @($versionA1, $currentA, $notificationsA) @(
    "", "1", $tenantA, $snapshot1, (Get-ContentHash $snapshot1), $effectiveAt, "", $activatedAt, $notification1
)
Assert-Reason $publish1 $true "SNAPSHOT_PUBLISHED"

$current = Invoke-SnapshotScript "read-current.lua" @($currentA) @($tenantA)
Assert-Reason $current $true "SNAPSHOT_CURRENT_READ"
if ($current.snapshot.config_version -ne "1") {
    throw "Initial current pointer did not select version 1"
}

$wrongCas = Invoke-SnapshotScript "publish.lua" @($versionA2, $currentA, $notificationsA) @(
    "999", "2", $tenantA, $snapshot2, (Get-ContentHash $snapshot2), $effectiveAt, "1", $activatedAt, $notification2
)
Assert-Reason $wrongCas $false "SNAPSHOT_CURRENT_VERSION_CONFLICT"
$currentAfterCasFailure = Invoke-SnapshotScript "read-current.lua" @($currentA) @($tenantA)
if ($currentAfterCasFailure.snapshot.config_version -ne "1") {
    throw "CAS rejection changed the old valid current pointer"
}

$publish2 = Invoke-SnapshotScript "publish.lua" @($versionA2, $currentA, $notificationsA) @(
    "1", "2", $tenantA, $snapshot2, (Get-ContentHash $snapshot2), $effectiveAt, "1", $activatedAt, $notification2
)
Assert-Reason $publish2 $true "SNAPSHOT_PUBLISHED"

foreach ($versionRead in @(
    (Invoke-SnapshotScript "read-version.lua" @($versionA1) @($tenantA, "1")),
    (Invoke-SnapshotScript "read-version.lua" @($versionA2) @($tenantA, "2"))
)) {
    Assert-Reason $versionRead $true "SNAPSHOT_VERSION_READ"
}

$changedSnapshot1 = $snapshot1.Replace("smart-chat", "changed-chat")
$immutableConflict = Invoke-SnapshotScript "publish.lua" @($versionA1, $currentA, $notificationsA) @(
    "2", "1", $tenantA, $changedSnapshot1, (Get-ContentHash $changedSnapshot1), $effectiveAt, "", $activatedAt, ([Guid]::NewGuid().ToString())
)
Assert-Reason $immutableConflict $false "SNAPSHOT_VERSION_CONFLICT"

$sensitiveField = "access_" + "token"
$sensitiveObject = [ordered]@{
    config_version = 3
    tenant_id = $tenantA
    model_alias = "smart-chat"
    policy_ids = @()
    route_strategy = "latency_cost_weighted"
    providers = @("provider-ap")
}
$sensitiveObject[$sensitiveField] = "blocked-value"
$sensitivePayload = $sensitiveObject | ConvertTo-Json -Compress
$versionA3 = "runtime-snapshot:{$tenantA}:version:3"
$sensitiveResult = Invoke-SnapshotScript "publish.lua" @($versionA3, $currentA, $notificationsA) @(
    "2", "3", $tenantA, $sensitivePayload, (Get-ContentHash $sensitivePayload), $effectiveAt, "2", $activatedAt, ([Guid]::NewGuid().ToString())
)
Assert-Reason $sensitiveResult $false "SNAPSHOT_PLAINTEXT_CREDENTIAL_FIELD_FORBIDDEN"

$currentB = "runtime-snapshot:{$tenantB}:current"
$tenantBMissing = Invoke-SnapshotScript "read-current.lua" @($currentB) @($tenantB)
Assert-Reason $tenantBMissing $true "SNAPSHOT_CURRENT_MISSING"
$crossTenantRead = Invoke-SnapshotScript "read-current.lua" @($currentA) @($tenantB)
Assert-Reason $crossTenantRead $false "SNAPSHOT_TENANT_KEY_MISMATCH"

$rollback = Invoke-SnapshotScript "rollback.lua" @($versionA1, $currentA, $notificationsA) @(
    "2", "1", $tenantA, ([DateTimeOffset]::UtcNow.ToString("o")), ([Guid]::NewGuid().ToString())
)
Assert-Reason $rollback $true "SNAPSHOT_ROLLED_BACK"
$currentAfterRollback = Invoke-SnapshotScript "read-current.lua" @($currentA) @($tenantA)
if ($currentAfterRollback.snapshot.config_version -ne "1" -or $currentAfterRollback.snapshot.transition_reason -ne "ROLLBACK") {
    throw "Rollback did not atomically select retained version 1"
}

$retainedVersion2 = Invoke-SnapshotScript "read-version.lua" @($versionA2) @($tenantA, "2")
Assert-Reason $retainedVersion2 $true "SNAPSHOT_VERSION_READ"

$notificationCount = [int]((Invoke-RedisClient @("XLEN", $notificationsA)) -join "")
if ($notificationCount -ne 3) {
    throw "Expected exactly one notification for each successful publish/rollback transition"
}
$notificationEntries = (Invoke-RedisClient @("XRANGE", $notificationsA, "-", "+")) -join "`n"
foreach ($requiredNotificationValue in @("schema_version", "notification_id", $tenantA, "PUBLISH", "ROLLBACK")) {
    if ($notificationEntries.IndexOf($requiredNotificationValue, [System.StringComparison]::Ordinal) -lt 0) {
        throw "Notification stream is missing required value: $requiredNotificationValue"
    }
}

Write-Output "status=pass reason_code=REDIS_SNAPSHOT_STORE_INTEGRATION_OK"
