using EnterpriseAiPlatform.Gateway.Domain.Contracts;

namespace EnterpriseAiPlatform.Gateway.Domain.Policy;

public sealed record PolicyPrincipal(string SubjectId, string TenantId, IReadOnlyList<string> Scopes)
{
    public PolicyPrincipal(string subjectId, string tenantId, IEnumerable<string> scopes)
        : this(Require(subjectId), Require(tenantId), CopyDistinct(scopes))
    {
    }

    private static string Require(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        return value;
    }

    private static IReadOnlyList<string> CopyDistinct(IEnumerable<string> values)
    {
        ArgumentNullException.ThrowIfNull(values);
        var copy = values.Select(Require).ToArray();
        if (copy.Distinct(StringComparer.Ordinal).Count() != copy.Length)
        {
            throw new ArgumentException("Scopes must be unique.", nameof(values));
        }

        return Array.AsReadOnly(copy);
    }
}

public sealed record PolicyResource
{
    public PolicyResource(string modelAlias, string region, decimal estimatedCost)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(modelAlias);
        ArgumentException.ThrowIfNullOrWhiteSpace(region);
        ArgumentOutOfRangeException.ThrowIfNegative(estimatedCost);
        ModelAlias = modelAlias;
        Region = region;
        EstimatedCost = estimatedCost;
    }

    public string ModelAlias { get; }
    public string Region { get; }
    public decimal EstimatedCost { get; }
}

public sealed record PolicyBudget
{
    public PolicyBudget(decimal monthSpend, decimal monthLimit)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(monthSpend);
        ArgumentOutOfRangeException.ThrowIfNegative(monthLimit);
        MonthSpend = monthSpend;
        MonthLimit = monthLimit;
    }

    public decimal MonthSpend { get; }
    public decimal MonthLimit { get; }
}

public sealed record PolicyObligation
{
    private PolicyObligation(
        string kind,
        string? target = null,
        string? region = null,
        bool? enabled = null,
        int? maxTokens = null)
    {
        Kind = kind;
        Target = target;
        Region = region;
        Enabled = enabled;
        MaxTokens = maxTokens;
    }

    public string Kind { get; }
    public string? Target { get; }
    public string? Region { get; }
    public bool? Enabled { get; }
    public int? MaxTokens { get; }

    public static PolicyObligation Mask(string target) =>
        new("mask", target: Require(target));

    public static PolicyObligation Redact(string target) =>
        new("redact", target: Require(target));

    public static PolicyObligation ForceRegion(string region) =>
        new("force_region", region: Require(region));

    public static PolicyObligation DisableBodyLogging() =>
        new("disable_body_logging", enabled: true);

    public static PolicyObligation LimitMaxTokens(int maxTokens)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(maxTokens, 1);
        return new PolicyObligation("limit_max_tokens", maxTokens: maxTokens);
    }

    private static string Require(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        return value;
    }
}

public sealed record PublishedPolicyContext
{
    public PublishedPolicyContext(
        string tenantId,
        long configVersion,
        ContractVersion policyVersion,
        IEnumerable<string> policyIds,
        string tenantStatus,
        IEnumerable<string> allowedModels,
        IEnumerable<string> allowedRegions,
        PolicyBudget budget,
        IEnumerable<PolicyObligation> obligations)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(tenantId);
        ArgumentOutOfRangeException.ThrowIfLessThan(configVersion, 1);
        ArgumentException.ThrowIfNullOrWhiteSpace(tenantStatus);
        ArgumentNullException.ThrowIfNull(budget);
        policyVersion.EnsureInitialized(nameof(policyVersion));
        TenantId = tenantId;
        ConfigVersion = configVersion;
        PolicyVersion = policyVersion;
        PolicyIds = CopyDistinct(policyIds, nameof(policyIds));
        TenantStatus = tenantStatus;
        AllowedModels = CopyDistinct(allowedModels, nameof(allowedModels));
        AllowedRegions = CopyDistinct(allowedRegions, nameof(allowedRegions));
        Budget = budget;
        Obligations = Array.AsReadOnly((obligations ?? throw new ArgumentNullException(nameof(obligations))).ToArray());
    }

    public string TenantId { get; }
    public long ConfigVersion { get; }
    public ContractVersion PolicyVersion { get; }
    public IReadOnlyList<string> PolicyIds { get; }
    public string TenantStatus { get; }
    public IReadOnlyList<string> AllowedModels { get; }
    public IReadOnlyList<string> AllowedRegions { get; }
    public PolicyBudget Budget { get; }
    public IReadOnlyList<PolicyObligation> Obligations { get; }

    private static IReadOnlyList<string> CopyDistinct(IEnumerable<string> values, string parameterName)
    {
        ArgumentNullException.ThrowIfNull(values, parameterName);
        var copy = values.ToArray();
        if (copy.Any(string.IsNullOrWhiteSpace) || copy.Distinct(StringComparer.Ordinal).Count() != copy.Length)
        {
            throw new ArgumentException("Values must be non-empty and unique.", parameterName);
        }

        return Array.AsReadOnly(copy);
    }
}

public sealed record PolicyEvaluationRequest
{
    public PolicyEvaluationRequest(
        string requestId,
        string traceId,
        string tenantId,
        long configVersion,
        PolicyPrincipal principal,
        PolicyResource resource,
        PublishedPolicyContext policyContext)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(requestId);
        ArgumentException.ThrowIfNullOrWhiteSpace(traceId);
        ArgumentException.ThrowIfNullOrWhiteSpace(tenantId);
        ArgumentOutOfRangeException.ThrowIfLessThan(configVersion, 1);
        RequestId = requestId;
        TraceId = traceId;
        TenantId = tenantId;
        ConfigVersion = configVersion;
        Principal = principal ?? throw new ArgumentNullException(nameof(principal));
        Resource = resource ?? throw new ArgumentNullException(nameof(resource));
        PolicyContext = policyContext ?? throw new ArgumentNullException(nameof(policyContext));
    }

    public int SchemaVersion => 1;
    public string RequestId { get; }
    public string TraceId { get; }
    public string TenantId { get; }
    public long ConfigVersion { get; }
    public PolicyPrincipal Principal { get; }
    public PolicyResource Resource { get; }
    public PublishedPolicyContext PolicyContext { get; }
}

public enum PolicyOutcome
{
    Allow,
    Deny,
    Indeterminate
}

public sealed record PolicyDecision
{
    public PolicyDecision(
        string requestId,
        string traceId,
        string tenantId,
        long configVersion,
        string modelAlias,
        PolicyOutcome outcome,
        string reasonCode,
        string? denyReason,
        IEnumerable<PolicyObligation> obligations,
        IEnumerable<string> matchedPolicyIds,
        ContractVersion policyVersion)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(requestId);
        ArgumentException.ThrowIfNullOrWhiteSpace(traceId);
        ArgumentException.ThrowIfNullOrWhiteSpace(tenantId);
        ArgumentException.ThrowIfNullOrWhiteSpace(modelAlias);
        ArgumentException.ThrowIfNullOrWhiteSpace(reasonCode);
        ArgumentOutOfRangeException.ThrowIfLessThan(configVersion, 1);
        policyVersion.EnsureInitialized(nameof(policyVersion));
        if (!IsReasonCode(reasonCode) || (denyReason is not null && !IsReasonCode(denyReason)))
        {
            throw new ArgumentException("Reason codes must use uppercase structured identifiers.", nameof(reasonCode));
        }
        if (outcome == PolicyOutcome.Deny && string.IsNullOrWhiteSpace(denyReason))
        {
            throw new ArgumentException("A deny decision requires deny_reason.", nameof(denyReason));
        }
        if (outcome != PolicyOutcome.Deny && denyReason is not null)
        {
            throw new ArgumentException("Only a deny decision may carry deny_reason.", nameof(denyReason));
        }

        var obligationCopy = (obligations ?? throw new ArgumentNullException(nameof(obligations))).ToArray();
        if (outcome == PolicyOutcome.Indeterminate && obligationCopy.Length != 0)
        {
            throw new ArgumentException("An indeterminate decision cannot carry obligations.", nameof(obligations));
        }

        var policyIdCopy = (matchedPolicyIds ?? throw new ArgumentNullException(nameof(matchedPolicyIds))).ToArray();
        if (policyIdCopy.Any(string.IsNullOrWhiteSpace) || policyIdCopy.Distinct(StringComparer.Ordinal).Count() != policyIdCopy.Length)
        {
            throw new ArgumentException("Matched policy IDs must be non-empty and unique.", nameof(matchedPolicyIds));
        }

        RequestId = requestId;
        TraceId = traceId;
        TenantId = tenantId;
        ConfigVersion = configVersion;
        ModelAlias = modelAlias;
        Outcome = outcome;
        ReasonCode = reasonCode;
        DenyReason = denyReason;
        Obligations = Array.AsReadOnly(obligationCopy);
        MatchedPolicyIds = Array.AsReadOnly(policyIdCopy);
        PolicyVersion = policyVersion;
    }

    public int SchemaVersion => 1;
    public string RequestId { get; }
    public string TraceId { get; }
    public string TenantId { get; }
    public long ConfigVersion { get; }
    public string ModelAlias { get; }
    public PolicyOutcome Outcome { get; }
    public bool? Allow => Outcome switch
    {
        PolicyOutcome.Allow => true,
        PolicyOutcome.Deny => false,
        _ => null
    };
    public string ReasonCode { get; }
    public string? DenyReason { get; }
    public IReadOnlyList<PolicyObligation> Obligations { get; }
    public IReadOnlyList<string> MatchedPolicyIds { get; }
    public ContractVersion PolicyVersion { get; }

    public static PolicyDecision Indeterminate(PolicyEvaluationRequest request, string reasonCode) =>
        new(
            request.RequestId,
            request.TraceId,
            request.TenantId,
            request.ConfigVersion,
            request.Resource.ModelAlias,
            PolicyOutcome.Indeterminate,
            reasonCode,
            null,
            [],
            [],
            request.PolicyContext.PolicyVersion);

    private static bool IsReasonCode(string value) =>
        value.Length > 0 &&
        char.IsAsciiLetterUpper(value[0]) &&
        value.All(character => character == '_' || char.IsAsciiLetterUpper(character) || char.IsAsciiDigit(character));
}
