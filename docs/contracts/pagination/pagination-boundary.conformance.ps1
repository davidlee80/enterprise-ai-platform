[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$contractRoot = $PSScriptRoot
$querySchemaPath = Join-Path $contractRoot "pagination-query.v1.schema.json"
$resultSchemaPath = Join-Path $contractRoot "pagination-result.v1.schema.json"
$policySchemaPath = Join-Path $contractRoot "pagination-policy.v1.schema.json"
$boundaryPath = Join-Path $contractRoot "pagination-boundary.v1.json"
$baselinePath = Join-Path $contractRoot "pagination-compatibility-baseline.v1.json"

function Read-ContractJson {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "PAGINATION_CONTRACT_FILE_MISSING: $Path"
    }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$ReasonCode
    )

    if (-not $Condition) {
        throw $ReasonCode
    }
}

function Assert-RequiredFields {
    param(
        [object]$Schema,
        [object]$BaselineFields,
        [string]$ReasonCode
    )

    foreach ($field in @($BaselineFields)) {
        Assert-Condition (@($Schema.required) -contains [string]$field) ($ReasonCode + "_" + ([string]$field).ToUpperInvariant())
    }
}

function Copy-ContractObject {
    param([object]$Value)

    return $Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json
}

function Invoke-ReferencePaginationBoundary {
    param(
        [object]$Query,
        [object[]]$Records
    )

    $tenantRecords = @($Records |
        Where-Object { [string]$_.tenant_id -eq [string]$Query.tenant_id } |
        Sort-Object -Property id)

    $start = 0
    if ([string]$Query.strategy -eq "cursor") {
        if ($null -ne $Query.offset) {
            throw "PAGINATION_CURSOR_QUERY_CONTAINS_OFFSET"
        }
        if ($null -ne $Query.cursor) {
            $match = [regex]::Match([string]$Query.cursor, '^mock-position:([0-9]+)$')
            if (-not $match.Success) {
                return [PSCustomObject][ordered]@{
                    schema_version = 1
                    request_id = [string]$Query.request_id
                    trace_id = [string]$Query.trace_id
                    tenant_id = $Query.tenant_id
                    operation_id = [string]$Query.operation_id
                    config_version = [int]$Query.config_version
                    strategy = "cursor"
                    items = @()
                    has_more = $false
                    next_cursor = $null
                    next_offset = $null
                    reason_code = "PAGINATION_POSITION_INVALID"
                }
            }
            $start = [int]$match.Groups[1].Value
        }
    }
    elseif ([string]$Query.strategy -eq "offset") {
        if ($null -ne $Query.cursor -or $null -eq $Query.offset) {
            throw "PAGINATION_OFFSET_QUERY_POSITION_INVALID"
        }
        $start = [int]$Query.offset
    }
    else {
        throw "PAGINATION_STRATEGY_INVALID"
    }

    $items = @($tenantRecords | Select-Object -Skip $start -First ([int]$Query.page_size))
    $nextPosition = $start + $items.Count
    $hasMore = $nextPosition -lt $tenantRecords.Count
    $nextCursor = $null
    $nextOffset = $null
    if ($hasMore -and [string]$Query.strategy -eq "cursor") {
        $nextCursor = "mock-position:$nextPosition"
    }
    if ($hasMore -and [string]$Query.strategy -eq "offset") {
        $nextOffset = $nextPosition
    }

    return [PSCustomObject][ordered]@{
        schema_version = 1
        request_id = [string]$Query.request_id
        trace_id = [string]$Query.trace_id
        tenant_id = $Query.tenant_id
        operation_id = [string]$Query.operation_id
        config_version = [int]$Query.config_version
        strategy = [string]$Query.strategy
        items = $items
        has_more = $hasMore
        next_cursor = $nextCursor
        next_offset = $nextOffset
        reason_code = if ($hasMore) { "PAGINATION_PAGE_RETURNED" } else { "PAGINATION_COMPLETE" }
    }
}

$querySchema = Read-ContractJson $querySchemaPath
$resultSchema = Read-ContractJson $resultSchemaPath
$policySchema = Read-ContractJson $policySchemaPath
$boundary = Read-ContractJson $boundaryPath
$baseline = Read-ContractJson $baselinePath

foreach ($schema in @($querySchema, $resultSchema, $policySchema)) {
    Assert-Condition ($schema.'$schema' -eq "https://json-schema.org/draft/2020-12/schema") "PAGINATION_SCHEMA_DRAFT_INVALID"
    Assert-Condition ($schema.additionalProperties -eq $false) "PAGINATION_UNVERSIONED_EXTENSION_ALLOWED"
}

Assert-Condition ($querySchema.'$id' -eq $baseline.query_schema_id) "PAGINATION_QUERY_SCHEMA_ID_CHANGED"
Assert-Condition ($resultSchema.'$id' -eq $baseline.result_schema_id) "PAGINATION_RESULT_SCHEMA_ID_CHANGED"
Assert-Condition ($policySchema.'$id' -eq $baseline.policy_schema_id) "PAGINATION_POLICY_SCHEMA_ID_CHANGED"
Assert-RequiredFields $querySchema $baseline.required_query_fields "PAGINATION_QUERY_FIELD_REMOVED"
Assert-RequiredFields $resultSchema $baseline.required_result_fields "PAGINATION_RESULT_FIELD_REMOVED"
foreach ($strategy in @($baseline.candidate_strategies)) {
    Assert-Condition (@($querySchema.properties.strategy.enum) -contains [string]$strategy) "PAGINATION_CANDIDATE_REMOVED"
    Assert-Condition (@($resultSchema.properties.strategy.enum) -contains [string]$strategy) "PAGINATION_RESULT_CANDIDATE_REMOVED"
    Assert-Condition (@($boundary.strategy_selection.candidates) -contains [string]$strategy) "PAGINATION_BOUNDARY_CANDIDATE_REMOVED"
}

Assert-Condition ($boundary.status -eq "api-design-review-required") "PAGINATION_BOUNDARY_STATUS_INVALID"
Assert-Condition (@($boundary.requirements) -contains "TBD-006") "PAGINATION_TBD_TRACE_MISSING"
Assert-Condition ($boundary.strategy_selection.status -eq "TBD-006" -and $null -eq $boundary.strategy_selection.selected) "PAGINATION_STRATEGY_PREMATURELY_SELECTED"
Assert-Condition ($boundary.transport_binding.status -eq "TBD-006") "PAGINATION_TRANSPORT_STATUS_INVALID"
Assert-Condition ($null -eq $boundary.transport_binding.cursor_query_parameter -and
    $null -eq $boundary.transport_binding.offset_query_parameter -and
    $null -eq $boundary.transport_binding.page_size_query_parameter) "PAGINATION_QUERY_PARAMETER_PREMATURELY_SELECTED"
Assert-Condition ($null -eq $boundary.page_size_policy.default_page_size -and $null -eq $boundary.page_size_policy.maximum_page_size) "PAGINATION_PAGE_SIZE_PREMATURELY_SELECTED"
Assert-Condition ($null -eq $boundary.cursor_policy.codec_ref -and $null -eq $boundary.cursor_policy.expiry_seconds) "PAGINATION_CURSOR_POLICY_PREMATURELY_SELECTED"
Assert-Condition ($null -eq $boundary.consistency.strategy) "PAGINATION_CONSISTENCY_PREMATURELY_SELECTED"
Assert-Condition ($boundary.tenant_isolation.filter_before_pagination -eq $true) "PAGINATION_TENANT_FILTER_ORDER_INVALID"
Assert-Condition ($boundary.tenant_isolation.cross_tenant_position_reuse_forbidden -eq $true) "PAGINATION_CROSS_TENANT_POSITION_ALLOWED"
Assert-Condition ($boundary.configuration_lifecycle.versioned -eq $true -and $boundary.configuration_lifecycle.rollback_required -eq $true) "PAGINATION_VERSION_ROLLBACK_MISSING"
Assert-Condition ($policySchema.properties.decision_status.const -eq "TBD-006") "PAGINATION_POLICY_TBD_GUARD_MISSING"

$records = @(
    [PSCustomObject]@{ id = "a-01"; tenant_id = "tenant-a"; name = "one" },
    [PSCustomObject]@{ id = "b-01"; tenant_id = "tenant-b"; name = "secret-other-tenant" },
    [PSCustomObject]@{ id = "a-02"; tenant_id = "tenant-a"; name = "two" },
    [PSCustomObject]@{ id = "a-03"; tenant_id = "tenant-a"; name = "three" }
)
$baseQuery = [PSCustomObject][ordered]@{
    schema_version = 1
    request_id = "request-pagination-test"
    trace_id = "trace-pagination-test"
    tenant_id = "tenant-a"
    operation_id = "listModels"
    config_version = 42
    strategy = "cursor"
    page_size = 2
    cursor = $null
    offset = $null
}

$cursorFirst = Invoke-ReferencePaginationBoundary (Copy-ContractObject $baseQuery) $records
Assert-Condition ($cursorFirst.items.Count -eq 2 -and $cursorFirst.has_more -eq $true -and $cursorFirst.next_cursor -eq "mock-position:2") "PAGINATION_CURSOR_FIRST_PAGE_INVALID"
$cursorNextQuery = Copy-ContractObject $baseQuery
$cursorNextQuery.cursor = $cursorFirst.next_cursor
$cursorNext = Invoke-ReferencePaginationBoundary $cursorNextQuery $records
Assert-Condition ($cursorNext.items.Count -eq 1 -and $cursorNext.has_more -eq $false -and $null -eq $cursorNext.next_cursor) "PAGINATION_CURSOR_NEXT_PAGE_INVALID"

$offsetQuery = Copy-ContractObject $baseQuery
$offsetQuery.strategy = "offset"
$offsetQuery.offset = 0
$offsetFirst = Invoke-ReferencePaginationBoundary $offsetQuery $records
Assert-Condition ($offsetFirst.items.Count -eq 2 -and $offsetFirst.has_more -eq $true -and $offsetFirst.next_offset -eq 2) "PAGINATION_OFFSET_FIRST_PAGE_INVALID"
$offsetQuery.offset = $offsetFirst.next_offset
$offsetNext = Invoke-ReferencePaginationBoundary $offsetQuery $records
Assert-Condition ($offsetNext.items.Count -eq 1 -and $offsetNext.has_more -eq $false -and $null -eq $offsetNext.next_offset) "PAGINATION_OFFSET_NEXT_PAGE_INVALID"

foreach ($result in @($cursorFirst, $cursorNext, $offsetFirst, $offsetNext)) {
    Assert-Condition (@($result.items | Where-Object { $_.tenant_id -ne "tenant-a" }).Count -eq 0) "PAGINATION_CROSS_TENANT_DATA_DISCLOSED"
    Assert-Condition ($result.tenant_id -eq "tenant-a" -and $result.config_version -eq 42) "PAGINATION_TRACE_CONTEXT_LOST"
    Assert-Condition ([string]$result.reason_code -match '^[A-Z][A-Z0-9_]*$') "PAGINATION_REASON_CODE_INVALID"
}

$invalidCursorQuery = Copy-ContractObject $baseQuery
$invalidCursorQuery.cursor = "invalid"
$invalidCursor = Invoke-ReferencePaginationBoundary $invalidCursorQuery $records
Assert-Condition ($invalidCursor.reason_code -eq "PAGINATION_POSITION_INVALID" -and $invalidCursor.items.Count -eq 0) "PAGINATION_INVALID_POSITION_NOT_STRUCTURED"

Write-Output "status=pass reason_code=ADMIN_PAGINATION_CONTRACT_OK tbd=TBD-006 strategy=not-selected"
