using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using EnterpriseAiPlatform.Gateway.Application.Policy;
using EnterpriseAiPlatform.Gateway.Domain.Contracts;
using EnterpriseAiPlatform.Gateway.Domain.Policy;

namespace EnterpriseAiPlatform.Gateway.Infrastructure.Policy;

public sealed class OpaPolicyRuntime(HttpClient httpClient, OpaPolicyRuntimeOptions options) : IPolicyRuntime
{
    private static readonly HashSet<string> DecisionFields = new(StringComparer.Ordinal)
    {
        "schema_version",
        "request_id",
        "trace_id",
        "tenant_id",
        "config_version",
        "model_alias",
        "outcome",
        "allow",
        "reason_code",
        "deny_reason",
        "obligations",
        "matched_policy_ids",
        "policy_version"
    };

    private readonly HttpClient _httpClient = httpClient ?? throw new ArgumentNullException(nameof(httpClient));
    private readonly OpaPolicyRuntimeOptions _options = options ?? throw new ArgumentNullException(nameof(options));

    public async ValueTask<PolicyDecision> EvaluateAsync(
        PolicyEvaluationRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();

        using var message = new HttpRequestMessage(HttpMethod.Post, _options.DecisionPath)
        {
            Content = new StringContent(
                BuildRequest(request).ToJsonString(),
                Encoding.UTF8,
                "application/json")
        };
        message.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        HttpResponseMessage response;
        try
        {
            response = await _httpClient.SendAsync(
                message,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException)
        {
            return PolicyDecision.Indeterminate(request, "POLICY_RUNTIME_TIMEOUT");
        }
        catch (HttpRequestException)
        {
            return PolicyDecision.Indeterminate(request, "POLICY_RUNTIME_UNAVAILABLE");
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                return PolicyDecision.Indeterminate(request, "POLICY_RUNTIME_HTTP_ERROR");
            }

            try
            {
                await using var stream = await response.Content
                    .ReadAsStreamAsync(cancellationToken)
                    .ConfigureAwait(false);
                using var document = await JsonDocument
                    .ParseAsync(stream, cancellationToken: cancellationToken)
                    .ConfigureAwait(false);
                if (!document.RootElement.TryGetProperty("result", out var result))
                {
                    return PolicyDecision.Indeterminate(request, "POLICY_RUNTIME_DOCUMENT_UNDEFINED");
                }

                return ParseDecision(result);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception) when (
                exception is JsonException or InvalidOperationException or ArgumentException or OverflowException or IOException)
            {
                return PolicyDecision.Indeterminate(request, "POLICY_RUNTIME_RESULT_INVALID");
            }
        }
    }

    private static JsonObject BuildRequest(PolicyEvaluationRequest request) =>
        new()
        {
            ["input"] = new JsonObject
            {
                ["schema_version"] = request.SchemaVersion,
                ["request_id"] = request.RequestId,
                ["trace_id"] = request.TraceId,
                ["tenant_id"] = request.TenantId,
                ["config_version"] = request.ConfigVersion,
                ["principal"] = new JsonObject
                {
                    ["subject_id"] = request.Principal.SubjectId,
                    ["tenant_id"] = request.Principal.TenantId,
                    ["scopes"] = StringArray(request.Principal.Scopes)
                },
                ["resource"] = new JsonObject
                {
                    ["model_alias"] = request.Resource.ModelAlias,
                    ["region"] = request.Resource.Region,
                    ["estimated_cost"] = request.Resource.EstimatedCost
                },
                ["policy_context"] = new JsonObject
                {
                    ["tenant_id"] = request.PolicyContext.TenantId,
                    ["config_version"] = request.PolicyContext.ConfigVersion,
                    ["policy_version"] = VersionNode(request.PolicyContext.PolicyVersion),
                    ["policy_ids"] = StringArray(request.PolicyContext.PolicyIds),
                    ["tenant_status"] = request.PolicyContext.TenantStatus,
                    ["allowed_models"] = StringArray(request.PolicyContext.AllowedModels),
                    ["allowed_regions"] = StringArray(request.PolicyContext.AllowedRegions),
                    ["budget"] = new JsonObject
                    {
                        ["month_spend"] = request.PolicyContext.Budget.MonthSpend,
                        ["month_limit"] = request.PolicyContext.Budget.MonthLimit
                    },
                    ["obligations"] = new JsonArray(request.PolicyContext.Obligations.Select(ObligationNode).ToArray())
                }
            }
        };

    private static PolicyDecision ParseDecision(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object ||
            element.EnumerateObject().Any(property => !DecisionFields.Contains(property.Name)) ||
            element.EnumerateObject().Count() != DecisionFields.Count ||
            element.GetProperty("schema_version").GetInt32() != 1)
        {
            throw new JsonException("OPA decision is not a closed Policy Decision v1 object.");
        }

        var outcomeText = RequiredString(element, "outcome");
        var outcome = outcomeText switch
        {
            "allow" => PolicyOutcome.Allow,
            "deny" => PolicyOutcome.Deny,
            "indeterminate" => PolicyOutcome.Indeterminate,
            _ => throw new JsonException("Unknown policy outcome.")
        };
        var allowElement = element.GetProperty("allow");
        var allow = allowElement.ValueKind == JsonValueKind.Null ? (bool?)null : allowElement.GetBoolean();
        if ((outcome == PolicyOutcome.Allow && allow != true) ||
            (outcome == PolicyOutcome.Deny && allow != false) ||
            (outcome == PolicyOutcome.Indeterminate && allow is not null))
        {
            throw new JsonException("Policy outcome and allow disagree.");
        }

        var denyReasonElement = element.GetProperty("deny_reason");
        var denyReason = denyReasonElement.ValueKind == JsonValueKind.Null
            ? null
            : denyReasonElement.GetString();
        var reasonCode = RequiredString(element, "reason_code");
        if (!IsReasonCode(reasonCode) || (denyReason is not null && !IsReasonCode(denyReason)))
        {
            throw new JsonException("Policy reason code is invalid.");
        }

        var obligations = element.GetProperty("obligations")
            .EnumerateArray()
            .Select(ParseObligation)
            .ToArray();
        var matchedPolicyIds = element.GetProperty("matched_policy_ids")
            .EnumerateArray()
            .Select(item => item.GetString() ?? throw new JsonException("Policy ID is null."))
            .ToArray();

        return new PolicyDecision(
            RequiredString(element, "request_id"),
            RequiredString(element, "trace_id"),
            RequiredString(element, "tenant_id"),
            element.GetProperty("config_version").GetInt64(),
            RequiredString(element, "model_alias"),
            outcome,
            reasonCode,
            denyReason,
            obligations,
            matchedPolicyIds,
            ParseVersion(element.GetProperty("policy_version")));
    }

    private static PolicyObligation ParseObligation(JsonElement element)
    {
        var kind = RequiredString(element, "kind");
        return kind switch
        {
            "mask" when HasOnly(element, "kind", "target") => PolicyObligation.Mask(RequiredString(element, "target")),
            "redact" when HasOnly(element, "kind", "target") => PolicyObligation.Redact(RequiredString(element, "target")),
            "force_region" when HasOnly(element, "kind", "region") => PolicyObligation.ForceRegion(RequiredString(element, "region")),
            "disable_body_logging" when HasOnly(element, "kind", "enabled") && element.GetProperty("enabled").GetBoolean() => PolicyObligation.DisableBodyLogging(),
            "limit_max_tokens" when HasOnly(element, "kind", "max_tokens") => PolicyObligation.LimitMaxTokens(element.GetProperty("max_tokens").GetInt32()),
            _ => throw new JsonException("Unknown or malformed policy obligation.")
        };
    }

    private static JsonObject ObligationNode(PolicyObligation obligation)
    {
        var node = new JsonObject { ["kind"] = obligation.Kind };
        switch (obligation.Kind)
        {
            case "mask":
            case "redact":
                node["target"] = obligation.Target;
                break;
            case "force_region":
                node["region"] = obligation.Region;
                break;
            case "disable_body_logging":
                node["enabled"] = obligation.Enabled;
                break;
            case "limit_max_tokens":
                node["max_tokens"] = obligation.MaxTokens;
                break;
            default:
                throw new InvalidOperationException("Unsupported policy obligation.");
        }

        return node;
    }

    private static JsonArray StringArray(IEnumerable<string> values) =>
        new(values.Select(value => JsonValue.Create(value)).ToArray());

    private static JsonNode VersionNode(ContractVersion version) => version.IsNumber
        ? JsonValue.Create(version.Number!.Value)
        : JsonValue.Create(version.Text!);

    private static ContractVersion ParseVersion(JsonElement element) => element.ValueKind switch
    {
        JsonValueKind.Number => ContractVersion.FromNumber(element.GetInt64()),
        JsonValueKind.String => ContractVersion.FromText(element.GetString()!),
        _ => throw new JsonException("Policy version is invalid.")
    };

    private static string RequiredString(JsonElement element, string propertyName)
    {
        var value = element.GetProperty(propertyName).GetString();
        return string.IsNullOrWhiteSpace(value)
            ? throw new JsonException($"{propertyName} is required.")
            : value;
    }

    private static bool HasOnly(JsonElement element, params string[] names)
    {
        var expected = names.ToHashSet(StringComparer.Ordinal);
        return element.ValueKind == JsonValueKind.Object &&
               element.EnumerateObject().Count() == expected.Count &&
               element.EnumerateObject().All(property => expected.Contains(property.Name));
    }

    private static bool IsReasonCode(string value) =>
        value.Length > 0 &&
        char.IsAsciiLetterUpper(value[0]) &&
        value.All(character => character == '_' || char.IsAsciiLetterUpper(character) || char.IsAsciiDigit(character));
}
