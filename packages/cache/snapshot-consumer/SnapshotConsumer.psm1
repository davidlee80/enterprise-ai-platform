Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not ("EnterpriseAIPlatform.RuntimeSnapshots.AtomicSnapshotSlot" -as [type])) {
    Add-Type -LiteralPath (Join-Path $PSScriptRoot "AtomicSnapshotSlot.cs")
}

function New-ConsumerResult {
    param(
        [bool]$Ok,
        [string]$ReasonCode,
        [string]$TenantId,
        [string]$ConfigVersion,
        [hashtable]$Additional = @{}
    )

    $result = [ordered]@{
        ok = $Ok
        reason_code = $ReasonCode
        tenant_id = $TenantId
        config_version = $ConfigVersion
    }
    foreach ($key in $Additional.Keys) {
        $result[$key] = $Additional[$key]
    }
    return [PSCustomObject]$result
}

function Get-ObjectProperty {
    param(
        [object]$InputObject,
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Test-PositiveVersion {
    param([object]$Value)

    return $null -ne $Value -and ([string]$Value) -match '^[1-9][0-9]*$'
}

function Compare-ConfigVersion {
    param(
        [string]$Left,
        [string]$Right
    )

    if ($Left.Length -lt $Right.Length) {
        return -1
    }
    if ($Left.Length -gt $Right.Length) {
        return 1
    }
    return [string]::CompareOrdinal($Left, $Right)
}

function Get-Sha256 {
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

function Test-StringArray {
    param(
        [object]$Value,
        [bool]$AllowEmpty
    )

    if ($null -eq $Value -or $Value -is [string] -or -not ($Value -is [System.Collections.IEnumerable])) {
        return $false
    }
    $items = @($Value)
    if (-not $AllowEmpty -and $items.Count -eq 0) {
        return $false
    }
    $unique = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($item in $items) {
        if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item) -or -not $unique.Add($item)) {
            return $false
        }
    }
    return $true
}

function Test-SensitiveField {
    param([object]$Value)

    if ($null -eq $Value -or $Value -is [string] -or $Value.GetType().IsPrimitive) {
        return $false
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Collections.IDictionary]) {
        foreach ($item in $Value) {
            if (Test-SensitiveField $item) {
                return $true
            }
        }
        return $false
    }

    foreach ($property in $Value.PSObject.Properties) {
        $field = $property.Name.ToLowerInvariant()
        $forbidden = $field -ne "secret_ref" -and (
            $field -eq "secret" -or
            $field -eq "token" -or
            $field -eq "credential" -or
            $field -eq "credentials" -or
            $field -eq "api_key" -or
            $field -eq "provider_key" -or
            $field.EndsWith("_token") -or
            $field.EndsWith("_api_key")
        )
        if ($forbidden -or (Test-SensitiveField $property.Value)) {
            return $true
        }
    }
    return $false
}

function ConvertTo-RoundTripTimestamp {
    param([object]$Value)

    $parsed = [DateTimeOffset]::MinValue
    $valid = $null -ne $Value -and [DateTimeOffset]::TryParse(
        [string]$Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsed
    )
    if (-not $valid) {
        return $null
    }
    return $parsed
}

function New-RuntimeSnapshotConsumer {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$MaximumStalenessSeconds = $null,
        [AllowNull()]
        [object]$OnStale = $null
    )

    if ($null -ne $MaximumStalenessSeconds) {
        $parsedMaximum = 0.0
        if (-not [double]::TryParse(
            [string]$MaximumStalenessSeconds,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsedMaximum
        ) -or $parsedMaximum -le 0) {
            throw "maximum staleness must be a positive number when configured"
        }
        $MaximumStalenessSeconds = $parsedMaximum
    }
    if ($null -ne $OnStale -and $OnStale -notin @("fail_open", "fail_closed")) {
        throw "on-stale behavior must be fail_open or fail_closed when configured"
    }
    if ($null -ne $OnStale) {
        $OnStale = [string]$OnStale
    }

    return [PSCustomObject]@{
        Slots = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string,object]'
        TenantLocks = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string,object]'
        MaximumStalenessSeconds = $MaximumStalenessSeconds
        OnStale = $OnStale
    }
}

function Get-TenantSlot {
    param(
        [object]$Consumer,
        [string]$TenantId
    )

    $candidate = New-Object EnterpriseAIPlatform.RuntimeSnapshots.AtomicSnapshotSlot
    return $Consumer.Slots.GetOrAdd($TenantId, $candidate)
}

function Get-RuntimeSnapshotLease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Consumer,
        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )

    $slot = $null
    if (-not $Consumer.Slots.TryGetValue($TenantId, [ref]$slot)) {
        return New-ConsumerResult $false "SNAPSHOT_NOT_LOADED" $TenantId ""
    }
    $active = $slot.Capture()
    if ($null -eq $active) {
        return New-ConsumerResult $false "SNAPSHOT_NOT_LOADED" $TenantId ""
    }
    return New-ConsumerResult $true "SNAPSHOT_LEASE_CAPTURED" $TenantId $active.config_version @{
        snapshot = $active
    }
}

function Invoke-RuntimeSnapshotNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Consumer,
        [Parameter(Mandatory = $true)]
        [object]$Notification,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ReadCurrent,
        [Parameter(Mandatory = $true)]
        [scriptblock]$FetchVersion,
        [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
    )

    $allowedNotificationFields = @(
        "schema_version",
        "notification_id",
        "tenant_id",
        "config_version",
        "content_hash",
        "activated_at",
        "transition_reason"
    )
    foreach ($property in $Notification.PSObject.Properties) {
        if ($allowedNotificationFields -cnotcontains $property.Name) {
            return New-ConsumerResult $false "SNAPSHOT_NOTIFICATION_INVALID" "" ""
        }
    }

    $schemaVersion = Get-ObjectProperty $Notification "schema_version"
    $notificationId = [string](Get-ObjectProperty $Notification "notification_id")
    $tenantId = [string](Get-ObjectProperty $Notification "tenant_id")
    $configVersionValue = Get-ObjectProperty $Notification "config_version"
    $configVersion = [string]$configVersionValue
    $contentHashValue = [string](Get-ObjectProperty $Notification "content_hash")
    $contentHash = $contentHashValue.ToLowerInvariant()
    $activatedAt = ConvertTo-RoundTripTimestamp (Get-ObjectProperty $Notification "activated_at")
    $transitionReason = [string](Get-ObjectProperty $Notification "transition_reason")

    if ($schemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace($notificationId) -or
        [string]::IsNullOrWhiteSpace($tenantId) -or $tenantId -match '[{}]' -or
        $configVersionValue -is [string] -or -not (Test-PositiveVersion $configVersion) -or
        $contentHashValue -cnotmatch '^[0-9a-f]{64}$' -or
        $null -eq $activatedAt -or
        $transitionReason -cnotin @("PUBLISH", "ROLLBACK")) {
        return New-ConsumerResult $false "SNAPSHOT_NOTIFICATION_INVALID" $tenantId $configVersion
    }

    $tenantLock = $Consumer.TenantLocks.GetOrAdd($tenantId, (New-Object object))
    [System.Threading.Monitor]::Enter($tenantLock)
    try {
        $slot = Get-TenantSlot $Consumer $tenantId
        $active = $slot.Capture()
        if ($null -ne $active) {
            $comparison = Compare-ConfigVersion $configVersion ([string]$active.config_version)
            if ($comparison -eq 0 -and $contentHash -eq $active.content_hash) {
                return New-ConsumerResult $true "SNAPSHOT_NOTIFICATION_DUPLICATE" $tenantId $configVersion
            }
            if ($comparison -eq 0) {
                return New-ConsumerResult $false "SNAPSHOT_ACTIVE_VERSION_CONFLICT" $tenantId $configVersion
            }
            if ($transitionReason -eq "PUBLISH" -and $comparison -lt 0) {
                return New-ConsumerResult $true "SNAPSHOT_NOTIFICATION_STALE" $tenantId $configVersion
            }
            if ($transitionReason -eq "ROLLBACK" -and $comparison -gt 0) {
                return New-ConsumerResult $false "SNAPSHOT_ROLLBACK_ORDER_INVALID" $tenantId $configVersion
            }
        }

        try {
            $currentResponse = & $ReadCurrent $tenantId
        }
        catch {
            return New-ConsumerResult $false "SNAPSHOT_CURRENT_READ_FAILED" $tenantId $configVersion
        }
        if ($null -eq $currentResponse) {
            return New-ConsumerResult $false "SNAPSHOT_CURRENT_READ_FAILED" $tenantId $configVersion
        }
        $currentResponseOk = Get-ObjectProperty $currentResponse "ok"
        if ($null -ne $currentResponseOk) {
            $currentFound = Get-ObjectProperty $currentResponse "found"
            $currentRecord = Get-ObjectProperty $currentResponse "snapshot"
            if (-not [bool]$currentResponseOk -or $currentFound -eq $false -or $null -eq $currentRecord) {
                return New-ConsumerResult $false "SNAPSHOT_CURRENT_READ_FAILED" $tenantId $configVersion
            }
            $currentResponse = $currentRecord
        }
        $pointerTenant = [string](Get-ObjectProperty $currentResponse "tenant_id")
        $pointerVersion = [string](Get-ObjectProperty $currentResponse "config_version")
        $pointerHash = ([string](Get-ObjectProperty $currentResponse "content_hash")).ToLowerInvariant()
        $pointerTransition = [string](Get-ObjectProperty $currentResponse "transition_reason")
        if ($pointerTenant -ne $tenantId -or $pointerVersion -ne $configVersion -or
            $pointerHash -ne $contentHash -or $pointerTransition -cne $transitionReason) {
            return New-ConsumerResult $false "SNAPSHOT_NOTIFICATION_NOT_CURRENT" $tenantId $configVersion
        }

        try {
            $stored = & $FetchVersion $tenantId $configVersion
        }
        catch {
            return New-ConsumerResult $false "SNAPSHOT_FETCH_FAILED" $tenantId $configVersion
        }
        if ($null -eq $stored) {
            return New-ConsumerResult $false "SNAPSHOT_FETCH_FAILED" $tenantId $configVersion
        }
        $storedResponseOk = Get-ObjectProperty $stored "ok"
        if ($null -ne $storedResponseOk) {
            $storedFound = Get-ObjectProperty $stored "found"
            $storedRecord = Get-ObjectProperty $stored "snapshot"
            if (-not [bool]$storedResponseOk -or $storedFound -eq $false -or $null -eq $storedRecord) {
                return New-ConsumerResult $false "SNAPSHOT_FETCH_FAILED" $tenantId $configVersion
            }
            $stored = $storedRecord
        }

        $storedTenant = [string](Get-ObjectProperty $stored "tenant_id")
        $storedVersion = [string](Get-ObjectProperty $stored "config_version")
        $snapshotJson = [string](Get-ObjectProperty $stored "snapshot_json")
        $storedHash = ([string](Get-ObjectProperty $stored "content_hash")).ToLowerInvariant()
        $effectiveAt = ConvertTo-RoundTripTimestamp (Get-ObjectProperty $stored "effective_at")
        if ($storedTenant -ne $tenantId -or $storedVersion -ne $configVersion -or
            [string]::IsNullOrWhiteSpace($snapshotJson) -or $storedHash -ne $contentHash -or
            (Get-Sha256 $snapshotJson) -ne $contentHash -or $null -eq $effectiveAt) {
            return New-ConsumerResult $false "SNAPSHOT_STORED_METADATA_INVALID" $tenantId $configVersion
        }

        try {
            $snapshot = $snapshotJson | ConvertFrom-Json
        }
        catch {
            return New-ConsumerResult $false "SNAPSHOT_PAYLOAD_JSON_INVALID" $tenantId $configVersion
        }

        $snapshotVersionValue = Get-ObjectProperty $snapshot "config_version"
        $snapshotVersion = [string]$snapshotVersionValue
        $snapshotTenant = [string](Get-ObjectProperty $snapshot "tenant_id")
        $modelAlias = [string](Get-ObjectProperty $snapshot "model_alias")
        $routeStrategy = [string](Get-ObjectProperty $snapshot "route_strategy")
        $policyIds = $null
        $providers = $null
        $policyProperty = $snapshot.PSObject.Properties["policy_ids"]
        $providersProperty = $snapshot.PSObject.Properties["providers"]
        if ($null -ne $policyProperty) {
            $policyIds = $policyProperty.Value
        }
        if ($null -ne $providersProperty) {
            $providers = $providersProperty.Value
        }
        if ($snapshotVersionValue -is [string] -or $snapshotVersion -ne $configVersion -or $snapshotTenant -ne $tenantId -or
            [string]::IsNullOrWhiteSpace($modelAlias) -or [string]::IsNullOrWhiteSpace($routeStrategy) -or
            -not (Test-StringArray $policyIds $true) -or -not (Test-StringArray $providers $false)) {
            return New-ConsumerResult $false "SNAPSHOT_CORE_FIELDS_INVALID" $tenantId $configVersion
        }
        if (Test-SensitiveField $snapshot) {
            return New-ConsumerResult $false "SNAPSHOT_PLAINTEXT_CREDENTIAL_FIELD_FORBIDDEN" $tenantId $configVersion
        }

        $candidate = [PSCustomObject]@{
            tenant_id = $tenantId
            config_version = $configVersion
            content_hash = $contentHash
            effective_at = $effectiveAt
            activated_at = $activatedAt
            loaded_at = $Now
            transition_reason = $transitionReason
            snapshot = $snapshot
        }
        $previous = $slot.Exchange($candidate)
        $previousVersion = if ($null -eq $previous) { "" } else { [string]$previous.config_version }
        return New-ConsumerResult $true "SNAPSHOT_ATOMIC_SWAP_APPLIED" $tenantId $configVersion @{
            previous_version = $previousVersion
            notification_id = $notificationId
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($tenantLock)
    }
}

function Sync-RuntimeSnapshotCurrent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Consumer,
        [Parameter(Mandatory = $true)]
        [string]$TenantId,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ReadCurrent,
        [Parameter(Mandatory = $true)]
        [scriptblock]$FetchVersion,
        [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
    )

    try {
        $currentResponse = & $ReadCurrent $TenantId
    }
    catch {
        return New-ConsumerResult $false "SNAPSHOT_CURRENT_READ_FAILED" $TenantId ""
    }
    if ($null -eq $currentResponse) {
        return New-ConsumerResult $false "SNAPSHOT_CURRENT_READ_FAILED" $TenantId ""
    }

    $responseOk = Get-ObjectProperty $currentResponse "ok"
    if ($null -ne $responseOk) {
        $found = Get-ObjectProperty $currentResponse "found"
        $current = Get-ObjectProperty $currentResponse "snapshot"
        if (-not [bool]$responseOk) {
            return New-ConsumerResult $false "SNAPSHOT_CURRENT_READ_FAILED" $TenantId ""
        }
        if ($found -eq $false -or $null -eq $current) {
            return New-ConsumerResult $false "SNAPSHOT_CURRENT_MISSING" $TenantId ""
        }
    }
    else {
        $current = $currentResponse
    }

    $currentTenant = [string](Get-ObjectProperty $current "tenant_id")
    $currentVersion = Get-ObjectProperty $current "config_version"
    $currentHash = [string](Get-ObjectProperty $current "content_hash")
    $activatedAt = Get-ObjectProperty $current "activated_at"
    $transitionReason = [string](Get-ObjectProperty $current "transition_reason")
    if ($currentTenant -ne $TenantId) {
        return New-ConsumerResult $false "SNAPSHOT_CURRENT_TENANT_MISMATCH" $TenantId ([string]$currentVersion)
    }

    $notification = [PSCustomObject]@{
        schema_version = 1
        notification_id = "reconcile:${TenantId}:${currentVersion}:${currentHash}"
        tenant_id = $currentTenant
        config_version = [long]$currentVersion
        content_hash = $currentHash
        activated_at = $activatedAt
        transition_reason = $transitionReason
    }
    return Invoke-RuntimeSnapshotNotification $Consumer $notification $ReadCurrent $FetchVersion -Now $Now
}

function Get-RuntimeSnapshotMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Consumer,
        [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
    )

    $samples = @()
    foreach ($entry in $Consumer.Slots.GetEnumerator()) {
        $active = $entry.Value.Capture()
        if ($null -eq $active) {
            continue
        }
        $staleness = [Math]::Max(0, ($Now - $active.effective_at).TotalSeconds)
        $propagation = [Math]::Max(0, ($active.loaded_at - $active.activated_at).TotalSeconds)
        $overMaximum = $null
        if ($null -ne $Consumer.MaximumStalenessSeconds) {
            $overMaximum = $staleness -gt [double]$Consumer.MaximumStalenessSeconds
        }
        $samples += [PSCustomObject]@{
            tenant_id = $active.tenant_id
            active_config_version = $active.config_version
            staleness_seconds = $staleness
            propagation_latency_seconds = $propagation
            maximum_staleness_seconds = $Consumer.MaximumStalenessSeconds
            over_maximum_staleness = $overMaximum
            on_stale = $Consumer.OnStale
            reason_code = "SNAPSHOT_METRICS_SAMPLED"
        }
    }
    return $samples
}

Export-ModuleMember -Function @(
    "New-RuntimeSnapshotConsumer",
    "Get-RuntimeSnapshotLease",
    "Invoke-RuntimeSnapshotNotification",
    "Sync-RuntimeSnapshotCurrent",
    "Get-RuntimeSnapshotMetrics"
)
