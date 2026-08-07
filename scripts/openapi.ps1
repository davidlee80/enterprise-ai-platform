[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("validate", "compatibility", "sdk-input")]
    [string]$Command
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$contractRelativePath = "docs/contracts/openapi/openapi.yaml"
$contractPath = Join-Path $repoRoot $contractRelativePath
$baselinePath = Join-Path $repoRoot "docs/contracts/openapi/compatibility-baseline.v1.json"
$bindingPath = Join-Path $repoRoot "apps/gateway/contracts/chat-completions.binding.v1.json"
$authenticationBoundaryRelativePath = "packages/auth/contracts/authentication-boundary.v1.json"
$authenticationBoundaryPath = Join-Path $repoRoot $authenticationBoundaryRelativePath
$fixtureRoot = Join-Path $repoRoot "docs/contracts/openapi/fixtures"
$script:Failures = @()

function Add-ContractFailure {
    param(
        [string]$ReasonCode,
        [string]$Subject,
        [string]$Detail
    )

    $script:Failures += [PSCustomObject]@{
        ReasonCode = $ReasonCode
        Subject = $Subject
        Detail = $Detail
    }
}

function Get-PropertyValue {
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

function Read-JsonDocument {
    param(
        [string]$Path,
        [string]$Subject,
        [string]$ReasonCode
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-ContractFailure "OPENAPI_FILE_MISSING" $Subject "required file is absent"
        return $null
    }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Add-ContractFailure $ReasonCode $Subject $_.Exception.Message
        return $null
    }
}

function Get-RequiredNames {
    param([object]$Schema)

    $required = Get-PropertyValue $Schema "required"
    if ($null -eq $required) {
        return @()
    }
    return @($required)
}

function Assert-RequiredFixtureFields {
    param(
        [object]$Fixture,
        [object]$Schema,
        [string]$Subject,
        [string]$ReasonCode
    )

    foreach ($field in (Get-RequiredNames $Schema)) {
        if ($null -eq $Fixture.PSObject.Properties[$field]) {
            Add-ContractFailure $ReasonCode $Subject ("required field is absent: " + $field)
        }
    }
}

function Find-LocalReferences {
    param(
        [object]$Value,
        [System.Collections.Generic.List[string]]$References
    )

    if ($null -eq $Value -or $Value -is [string] -or $Value.GetType().IsPrimitive) {
        return
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Collections.IDictionary]) {
        foreach ($item in $Value) {
            Find-LocalReferences $item $References
        }
        return
    }
    foreach ($property in $Value.PSObject.Properties) {
        if ($property.Name -eq '$ref') {
            $References.Add([string]$property.Value)
        }
        else {
            Find-LocalReferences $property.Value $References
        }
    }
}

function Assert-LocalReferences {
    param([object]$Document)

    $references = New-Object 'System.Collections.Generic.List[string]'
    Find-LocalReferences $Document $references
    foreach ($reference in $references) {
        if ($reference -notmatch '^#/components/(schemas|examples)/([^/]+)$') {
            Add-ContractFailure "OPENAPI_REFERENCE_UNSUPPORTED" $contractRelativePath ("reference must remain local and version-controlled: " + $reference)
            continue
        }
        $group = $Matches[1]
        $name = $Matches[2]
        $components = Get-PropertyValue $Document "components"
        $collection = Get-PropertyValue $components $group
        if ($null -eq $collection -or $null -eq $collection.PSObject.Properties[$name]) {
            Add-ContractFailure "OPENAPI_REFERENCE_UNRESOLVED" $contractRelativePath ("unresolved reference: " + $reference)
        }
    }
}

function Get-SchemaPropertySignature {
    param([object]$PropertySchema)

    $segments = @()
    $reference = [string](Get-PropertyValue $PropertySchema '$ref')
    if (-not [string]::IsNullOrWhiteSpace($reference)) {
        $segments += "ref=$reference"
    }
    $type = Get-PropertyValue $PropertySchema "type"
    if ($null -ne $type) {
        $types = @($type | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        $segments += ("type=" + ($types -join "|"))
    }
    $constant = Get-PropertyValue $PropertySchema "const"
    if ($null -ne $constant) {
        $segments += ("const=" + [string]$constant)
    }
    $enum = Get-PropertyValue $PropertySchema "enum"
    if ($null -ne $enum) {
        $values = @($enum | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        $segments += ("enum=" + ($values -join ","))
    }
    $oneOf = Get-PropertyValue $PropertySchema "oneOf"
    if ($null -ne $oneOf) {
        $alternatives = @($oneOf | ForEach-Object { Get-SchemaPropertySignature $_ } | Sort-Object -Unique)
        $segments += ("oneOf=" + ($alternatives -join "|"))
    }
    return $segments -join ";"
}

function Invoke-OpenApiValidation {
    $document = Read-JsonDocument $contractPath $contractRelativePath "OPENAPI_DOCUMENT_INVALID"
    if ($null -eq $document) {
        return $null
    }

    if ([string](Get-PropertyValue $document "openapi") -ne "3.1.0") {
        Add-ContractFailure "OPENAPI_VERSION_INVALID" $contractRelativePath "openapi must equal 3.1.0"
    }
    $info = Get-PropertyValue $document "info"
    if ([string](Get-PropertyValue $info "title") -ne "Enterprise AI Platform API") {
        Add-ContractFailure "OPENAPI_TITLE_INVALID" $contractRelativePath "API title does not match the development baseline"
    }
    if ([string](Get-PropertyValue $info "version") -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
        Add-ContractFailure "OPENAPI_INFO_VERSION_INVALID" $contractRelativePath "info.version must be SemVer"
    }
    if ($null -ne (Get-PropertyValue $document "servers")) {
        Add-ContractFailure "OPENAPI_PRODUCTION_SERVER_UNRESOLVED" $contractRelativePath "production domain is TBD-019 and must not be invented"
    }

    $paths = Get-PropertyValue $document "paths"
    $pathItem = Get-PropertyValue $paths "/v1/chat/completions"
    $operation = Get-PropertyValue $pathItem "post"
    if ($null -eq $operation) {
        Add-ContractFailure "OPENAPI_CHAT_OPERATION_MISSING" $contractRelativePath "POST /v1/chat/completions is required"
        return $document
    }
    if ([string](Get-PropertyValue $operation "operationId") -ne "createChatCompletion") {
        Add-ContractFailure "OPENAPI_OPERATION_ID_INVALID" $contractRelativePath "operationId must remain createChatCompletion"
    }

    $securityNames = @()
    foreach ($requirement in @((Get-PropertyValue $operation "security"))) {
        $securityNames += @($requirement.PSObject.Properties.Name)
    }
    foreach ($requiredSecurity in @("BearerAuth", "ApiKeyAuth")) {
        if ($securityNames -notcontains $requiredSecurity) {
            Add-ContractFailure "OPENAPI_AUTH_CAPABILITY_MISSING" $contractRelativePath ("missing security capability: " + $requiredSecurity)
        }
        $schemes = Get-PropertyValue (Get-PropertyValue $document "components") "securitySchemes"
        if ($null -eq $schemes.PSObject.Properties[$requiredSecurity]) {
            Add-ContractFailure "OPENAPI_SECURITY_SCHEME_UNRESOLVED" $contractRelativePath ("undefined security scheme: " + $requiredSecurity)
        }
    }
    if ([string](Get-PropertyValue $operation "x-authentication-tbd") -notmatch 'REQ-API-003') {
        Add-ContractFailure "OPENAPI_AUTH_TBD_GUARD_MISSING" $contractRelativePath "concrete API-key scheme/header must remain traceable to REQ-API-003"
    }
    if ([string](Get-PropertyValue $operation "x-authentication-contract") -ne "../../../packages/auth/contracts/authentication-boundary.v1.json") {
        Add-ContractFailure "OPENAPI_AUTH_CONTRACT_MISSING" $contractRelativePath "operation must reference Authentication Boundary v1"
    }
    $authenticationBoundary = Read-JsonDocument $authenticationBoundaryPath $authenticationBoundaryRelativePath "OPENAPI_AUTH_CONTRACT_INVALID"
    if ($null -ne $authenticationBoundary) {
        $normalizedKinds = @((Get-PropertyValue $authenticationBoundary "supported_credential_kinds"))
        $schemes = Get-PropertyValue (Get-PropertyValue $document "components") "securitySchemes"
        foreach ($mapping in @(
            [PSCustomObject]@{ Scheme = "BearerAuth"; Kind = "bearer" },
            [PSCustomObject]@{ Scheme = "ApiKeyAuth"; Kind = "api_key" }
        )) {
            $scheme = Get-PropertyValue $schemes $mapping.Scheme
            if ([string](Get-PropertyValue $scheme "x-credential-kind") -ne $mapping.Kind -or $normalizedKinds -notcontains $mapping.Kind) {
                Add-ContractFailure "OPENAPI_AUTH_CAPABILITY_MISMATCH" $contractRelativePath ("security capability is not synchronized with Authentication Boundary v1: " + $mapping.Scheme)
            }
        }
    }

    $requestBody = Get-PropertyValue $operation "requestBody"
    $requestContent = Get-PropertyValue (Get-PropertyValue $requestBody "content") "application/json"
    if ((Get-PropertyValue $requestBody "required") -ne $true -or
        [string](Get-PropertyValue (Get-PropertyValue $requestContent "schema") '$ref') -ne "#/components/schemas/CreateChatCompletionRequest") {
        Add-ContractFailure "OPENAPI_REQUEST_BODY_INVALID" $contractRelativePath "required JSON request schema is missing"
    }

    $responses = Get-PropertyValue $operation "responses"
    foreach ($status in @("200", "400", "401", "403", "429", "502")) {
        $response = Get-PropertyValue $responses $status
        if ($null -eq $response -or [string]::IsNullOrWhiteSpace([string](Get-PropertyValue $response "description"))) {
            Add-ContractFailure "OPENAPI_RESPONSE_STATUS_MISSING" $contractRelativePath ("missing response semantics: " + $status)
        }
    }
    $successContent = Get-PropertyValue (Get-PropertyValue $responses "200") "content"
    if ([string](Get-PropertyValue (Get-PropertyValue (Get-PropertyValue $successContent "application/json") "schema") '$ref') -ne "#/components/schemas/ChatCompletion") {
        Add-ContractFailure "OPENAPI_SUCCESS_SCHEMA_MISSING" $contractRelativePath "200 application/json schema is missing"
    }
    if ($null -eq (Get-PropertyValue $successContent "text/event-stream")) {
        Add-ContractFailure "OPENAPI_STREAM_RESPONSE_MISSING" $contractRelativePath "200 text/event-stream response is missing"
    }
    foreach ($status in @("400", "401", "403", "429", "502")) {
        $response = Get-PropertyValue $responses $status
        if ($null -ne (Get-PropertyValue $response "content")) {
            Add-ContractFailure "OPENAPI_ERROR_SCHEMA_PREMATURE" $contractRelativePath ("TBD-008 forbids inventing an error body for status " + $status)
        }
        if ([string](Get-PropertyValue $response "description") -notmatch 'TBD-008') {
            Add-ContractFailure "OPENAPI_ERROR_TBD_TRACE_MISSING" $contractRelativePath ("error status is not traceable to TBD-008: " + $status)
        }
    }

    $schemas = Get-PropertyValue (Get-PropertyValue $document "components") "schemas"
    $requestSchema = Get-PropertyValue $schemas "CreateChatCompletionRequest"
    $responseSchema = Get-PropertyValue $schemas "ChatCompletion"
    $chunkSchema = Get-PropertyValue $schemas "ChatCompletionChunk"
    foreach ($field in @("model", "messages")) {
        if ((Get-RequiredNames $requestSchema) -notcontains $field) {
            Add-ContractFailure "OPENAPI_REQUEST_FIELD_MISSING" $contractRelativePath ("required request field is absent: " + $field)
        }
    }
    foreach ($field in @("id", "object", "created", "model", "choices")) {
        if ((Get-RequiredNames $responseSchema) -notcontains $field) {
            Add-ContractFailure "OPENAPI_RESPONSE_FIELD_MISSING" $contractRelativePath ("required response field is absent: " + $field)
        }
        if ((Get-RequiredNames $chunkSchema) -notcontains $field) {
            Add-ContractFailure "OPENAPI_CHUNK_FIELD_MISSING" $contractRelativePath ("required stream field is absent: " + $field)
        }
    }
    if ((Get-PropertyValue $requestSchema "additionalProperties") -ne $true -or
        (Get-PropertyValue $responseSchema "additionalProperties") -ne $true) {
        Add-ContractFailure "OPENAPI_COMPATIBILITY_EXTENSION_BLOCKED" $contractRelativePath "baseline request/response must permit additive fields"
    }

    Assert-LocalReferences $document

    $requestFixture = Read-JsonDocument (Join-Path $fixtureRoot "chat-completion.request.valid.json") "chat-completion.request.valid.json" "OPENAPI_FIXTURE_INVALID"
    $responseFixture = Read-JsonDocument (Join-Path $fixtureRoot "chat-completion.response.valid.json") "chat-completion.response.valid.json" "OPENAPI_FIXTURE_INVALID"
    $chunkFixture = Read-JsonDocument (Join-Path $fixtureRoot "chat-completion.chunk.valid.json") "chat-completion.chunk.valid.json" "OPENAPI_FIXTURE_INVALID"
    $invalidRequestFixture = Read-JsonDocument (Join-Path $fixtureRoot "chat-completion.request.invalid.json") "chat-completion.request.invalid.json" "OPENAPI_FIXTURE_INVALID"
    if ($null -ne $requestFixture) {
        Assert-RequiredFixtureFields $requestFixture $requestSchema "chat-completion.request.valid.json" "OPENAPI_REQUEST_CONTRACT_FAILED"
        $messages = @(Get-PropertyValue $requestFixture "messages")
        if ($messages.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string](Get-PropertyValue $messages[0] "role"))) {
            Add-ContractFailure "OPENAPI_REQUEST_CONTRACT_FAILED" "chat-completion.request.valid.json" "at least one message with a role is required"
        }
    }
    if ($null -ne $responseFixture) {
        Assert-RequiredFixtureFields $responseFixture $responseSchema "chat-completion.response.valid.json" "OPENAPI_RESPONSE_CONTRACT_FAILED"
        if ([string](Get-PropertyValue $responseFixture "object") -ne "chat.completion") {
            Add-ContractFailure "OPENAPI_RESPONSE_CONTRACT_FAILED" "chat-completion.response.valid.json" "object must equal chat.completion"
        }
    }
    if ($null -ne $chunkFixture) {
        Assert-RequiredFixtureFields $chunkFixture $chunkSchema "chat-completion.chunk.valid.json" "OPENAPI_STREAM_CONTRACT_FAILED"
        if ([string](Get-PropertyValue $chunkFixture "object") -ne "chat.completion.chunk") {
            Add-ContractFailure "OPENAPI_STREAM_CONTRACT_FAILED" "chat-completion.chunk.valid.json" "object must equal chat.completion.chunk"
        }
    }
    if ($null -ne $invalidRequestFixture) {
        $missingRequired = @((Get-RequiredNames $requestSchema) | Where-Object { $null -eq $invalidRequestFixture.PSObject.Properties[$_] })
        if ($missingRequired -notcontains "model") {
            Add-ContractFailure "OPENAPI_NEGATIVE_FIXTURE_INVALID" "chat-completion.request.invalid.json" "negative fixture must prove model is required"
        }
    }

    $binding = Read-JsonDocument $bindingPath "apps/gateway/contracts/chat-completions.binding.v1.json" "OPENAPI_BINDING_INVALID"
    if ($null -ne $binding) {
        if ([string](Get-PropertyValue $binding "operation_id") -ne "createChatCompletion" -or
            [string](Get-PropertyValue $binding "method") -ne "POST" -or
            [string](Get-PropertyValue $binding "path") -ne "/v1/chat/completions" -or
            [string](Get-PropertyValue $binding "runtime_handler_status") -ne "TBD-001") {
            Add-ContractFailure "OPENAPI_HANDLER_BINDING_INVALID" "apps/gateway/contracts/chat-completions.binding.v1.json" "binding must match the operation and preserve the runtime-language TBD"
        }
    }

    return $document
}

function Invoke-CompatibilityCheck {
    param([object]$Document)

    $baseline = Read-JsonDocument $baselinePath "docs/contracts/openapi/compatibility-baseline.v1.json" "OPENAPI_BASELINE_INVALID"
    if ($null -eq $baseline -or $null -eq $Document) {
        return
    }
    $path = [string](Get-PropertyValue $baseline "path")
    $method = [string](Get-PropertyValue $baseline "method")
    $operation = Get-PropertyValue (Get-PropertyValue (Get-PropertyValue $Document "paths") $path) $method
    if ($null -eq $operation -or [string](Get-PropertyValue $operation "operationId") -ne [string](Get-PropertyValue $baseline "operation_id")) {
        Add-ContractFailure "OPENAPI_BREAKING_OPERATION_CHANGE" $contractRelativePath "baseline operation was removed or renamed"
        return
    }
    $responses = Get-PropertyValue $operation "responses"
    foreach ($status in @((Get-PropertyValue $baseline "required_statuses"))) {
        if ($null -eq $responses.PSObject.Properties[[string]$status]) {
            Add-ContractFailure "OPENAPI_BREAKING_RESPONSE_REMOVAL" $contractRelativePath ("baseline response was removed: " + $status)
        }
    }
    $schemas = Get-PropertyValue (Get-PropertyValue $Document "components") "schemas"
    $requestRequired = Get-RequiredNames (Get-PropertyValue $schemas "CreateChatCompletionRequest")
    $responseRequired = Get-RequiredNames (Get-PropertyValue $schemas "ChatCompletion")
    $baselineRequestFields = @((Get-PropertyValue $baseline "required_request_fields"))
    foreach ($field in $baselineRequestFields) {
        if ($requestRequired -notcontains $field) {
            Add-ContractFailure "OPENAPI_BREAKING_REQUEST_CHANGE" $contractRelativePath ("baseline request field was removed: " + $field)
        }
    }
    foreach ($field in $requestRequired) {
        if ($baselineRequestFields -notcontains $field) {
            Add-ContractFailure "OPENAPI_BREAKING_REQUIRED_REQUEST_ADDITION" $contractRelativePath ("new required request field needs an explicit breaking-change review: " + $field)
        }
    }
    foreach ($field in @((Get-PropertyValue $baseline "required_response_fields"))) {
        if ($responseRequired -notcontains $field) {
            Add-ContractFailure "OPENAPI_BREAKING_RESPONSE_CHANGE" $contractRelativePath ("baseline response field was removed: " + $field)
        }
    }
    $requestProperties = Get-PropertyValue (Get-PropertyValue $schemas "CreateChatCompletionRequest") "properties"
    $responseProperties = Get-PropertyValue (Get-PropertyValue $schemas "ChatCompletion") "properties"
    foreach ($property in (Get-PropertyValue $baseline "required_request_property_types").PSObject.Properties) {
        $actualType = [string](Get-PropertyValue (Get-PropertyValue $requestProperties $property.Name) "type")
        if ($actualType -ne [string]$property.Value) {
            Add-ContractFailure "OPENAPI_BREAKING_REQUEST_TYPE_CHANGE" $contractRelativePath ("request property type changed: " + $property.Name)
        }
    }
    foreach ($property in (Get-PropertyValue $baseline "required_response_property_types").PSObject.Properties) {
        $actualType = [string](Get-PropertyValue (Get-PropertyValue $responseProperties $property.Name) "type")
        if ($actualType -ne [string]$property.Value) {
            Add-ContractFailure "OPENAPI_BREAKING_RESPONSE_TYPE_CHANGE" $contractRelativePath ("response property type changed: " + $property.Name)
        }
    }
    $responseObjectConst = [string](Get-PropertyValue (Get-PropertyValue $responseProperties "object") "const")
    if ($responseObjectConst -ne [string](Get-PropertyValue $baseline "response_object_const")) {
        Add-ContractFailure "OPENAPI_BREAKING_RESPONSE_SEMANTIC_CHANGE" $contractRelativePath "chat completion object discriminator changed"
    }
    $successContent = Get-PropertyValue (Get-PropertyValue (Get-PropertyValue $operation "responses") "200") "content"
    foreach ($mediaType in @((Get-PropertyValue $baseline "required_success_media_types"))) {
        if ($null -eq $successContent.PSObject.Properties[[string]$mediaType]) {
            Add-ContractFailure "OPENAPI_BREAKING_MEDIA_TYPE_REMOVAL" $contractRelativePath ("baseline success media type was removed: " + $mediaType)
        }
    }
    $securityNames = @()
    foreach ($requirement in @((Get-PropertyValue $operation "security"))) {
        $securityNames += @($requirement.PSObject.Properties.Name)
    }
    foreach ($capability in @((Get-PropertyValue $baseline "required_security_capabilities"))) {
        if ($securityNames -notcontains $capability) {
            Add-ContractFailure "OPENAPI_BREAKING_SECURITY_CHANGE" $contractRelativePath ("baseline security capability was removed: " + $capability)
        }
    }
    $securitySchemes = Get-PropertyValue (Get-PropertyValue $Document "components") "securitySchemes"
    foreach ($property in (Get-PropertyValue $baseline "required_security_scheme_types").PSObject.Properties) {
        $scheme = Get-PropertyValue $securitySchemes $property.Name
        $actualSignature = ([string](Get-PropertyValue $scheme "type")) + ":" + ([string](Get-PropertyValue $scheme "scheme"))
        if ($actualSignature -cne [string]$property.Value) {
            Add-ContractFailure "OPENAPI_BREAKING_SECURITY_SCHEME_CHANGE" $contractRelativePath ("security scheme changed: " + $property.Name)
        }
    }
    foreach ($property in (Get-PropertyValue $baseline "required_security_credential_kinds").PSObject.Properties) {
        $scheme = Get-PropertyValue $securitySchemes $property.Name
        if ([string](Get-PropertyValue $scheme "x-credential-kind") -cne [string]$property.Value) {
            Add-ContractFailure "OPENAPI_BREAKING_SECURITY_CAPABILITY_CHANGE" $contractRelativePath ("normalized credential kind changed: " + $property.Name)
        }
    }
    foreach ($schemaBaseline in (Get-PropertyValue $baseline "schema_property_signatures").PSObject.Properties) {
        $schema = Get-PropertyValue $schemas $schemaBaseline.Name
        if ($null -eq $schema) {
            Add-ContractFailure "OPENAPI_BREAKING_SCHEMA_REMOVAL" $contractRelativePath ("baseline schema was removed: " + $schemaBaseline.Name)
            continue
        }
        $properties = Get-PropertyValue $schema "properties"
        foreach ($propertyBaseline in $schemaBaseline.Value.PSObject.Properties) {
            $propertySchema = Get-PropertyValue $properties $propertyBaseline.Name
            if ($null -eq $propertySchema) {
                Add-ContractFailure "OPENAPI_BREAKING_PROPERTY_REMOVAL" $contractRelativePath ("baseline schema property was removed: " + $schemaBaseline.Name + "." + $propertyBaseline.Name)
                continue
            }
            $actualSignature = Get-SchemaPropertySignature $propertySchema
            if ($actualSignature -cne [string]$propertyBaseline.Value) {
                Add-ContractFailure "OPENAPI_BREAKING_PROPERTY_CHANGE" $contractRelativePath ("baseline schema property changed: " + $schemaBaseline.Name + "." + $propertyBaseline.Name)
            }
        }
    }
}

$document = Invoke-OpenApiValidation
if ($Command -eq "compatibility") {
    Invoke-CompatibilityCheck $document
}

if ($script:Failures.Count -gt 0) {
    foreach ($failure in $script:Failures) {
        Write-Output ("status=fail command={0} reason_code={1} subject={2} detail={3}" -f $Command, $failure.ReasonCode, $failure.Subject, $failure.Detail)
    }
    exit 1
}

switch ($Command) {
    "validate" {
        Write-Output "status=pass command=validate reason_code=OPENAPI_3_1_CONTRACT_OK"
    }
    "compatibility" {
        Write-Output "status=pass command=compatibility reason_code=OPENAPI_V1_COMPATIBILITY_OK"
    }
    "sdk-input" {
        $hash = (Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Output ("status=pass command=sdk-input reason_code=SDK_GENERATION_INPUT_READY contract={0} sha256={1} sdk_language_set=TBD-007" -f $contractRelativePath, $hash)
    }
}
