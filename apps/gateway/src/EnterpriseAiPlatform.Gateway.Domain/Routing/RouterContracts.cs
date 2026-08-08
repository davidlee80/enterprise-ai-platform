using EnterpriseAiPlatform.Gateway.Domain.Contracts;
using EnterpriseAiPlatform.Gateway.Domain.Policy;

namespace EnterpriseAiPlatform.Gateway.Domain.Routing;

public sealed record RouterCandidate
{
    public RouterCandidate(string providerId, string region, int priority, int weight, bool enabled)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(providerId);
        ArgumentException.ThrowIfNullOrWhiteSpace(region);
        ArgumentOutOfRangeException.ThrowIfNegative(weight);
        ProviderId = providerId;
        Region = region;
        Priority = priority;
        Weight = weight;
        Enabled = enabled;
    }

    public string ProviderId { get; }
    public string Region { get; }
    public int Priority { get; }
    public int Weight { get; }
    public bool Enabled { get; }
}

public sealed record RouterRequest
{
    public RouterRequest(
        string requestId,
        string traceId,
        string tenantId,
        long configVersion,
        string modelAlias,
        string routeStrategy,
        PolicyOutcome policyOutcome,
        ContractVersion policyVersion,
        IEnumerable<PolicyObligation> obligations,
        IEnumerable<RouterCandidate> candidates)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(requestId);
        ArgumentException.ThrowIfNullOrWhiteSpace(traceId);
        ArgumentException.ThrowIfNullOrWhiteSpace(tenantId);
        ArgumentException.ThrowIfNullOrWhiteSpace(modelAlias);
        ArgumentException.ThrowIfNullOrWhiteSpace(routeStrategy);
        ArgumentOutOfRangeException.ThrowIfLessThan(configVersion, 1);
        policyVersion.EnsureInitialized(nameof(policyVersion));
        var candidateCopy = (candidates ?? throw new ArgumentNullException(nameof(candidates))).ToArray();
        if (candidateCopy.Length == 0)
        {
            throw new ArgumentException("At least one routing candidate is required.", nameof(candidates));
        }

        RequestId = requestId;
        TraceId = traceId;
        TenantId = tenantId;
        ConfigVersion = configVersion;
        ModelAlias = modelAlias;
        RouteStrategy = routeStrategy;
        PolicyOutcome = policyOutcome;
        PolicyVersion = policyVersion;
        Obligations = Array.AsReadOnly((obligations ?? throw new ArgumentNullException(nameof(obligations))).ToArray());
        Candidates = Array.AsReadOnly(candidateCopy);
    }

    public int SchemaVersion => 1;
    public string RequestId { get; }
    public string TraceId { get; }
    public string TenantId { get; }
    public long ConfigVersion { get; }
    public string ModelAlias { get; }
    public string RouteStrategy { get; }
    public PolicyOutcome PolicyOutcome { get; }
    public ContractVersion PolicyVersion { get; }
    public IReadOnlyList<PolicyObligation> Obligations { get; }
    public IReadOnlyList<RouterCandidate> Candidates { get; }
}

public sealed record RouterPluginContext
{
    public RouterPluginContext(RouterRequest request, IEnumerable<RouterCandidate> candidates)
    {
        Request = request ?? throw new ArgumentNullException(nameof(request));
        Candidates = Array.AsReadOnly((candidates ?? throw new ArgumentNullException(nameof(candidates))).ToArray());
    }

    public RouterRequest Request { get; }
    public IReadOnlyList<RouterCandidate> Candidates { get; }
}

public enum RouterPluginOutcome
{
    Applied,
    Skipped,
    Rejected,
    Indeterminate
}

public sealed record RouterPluginResult
{
    public RouterPluginResult(
        string pluginId,
        ContractVersion pluginVersion,
        RouterPluginOutcome outcome,
        string reasonCode,
        IEnumerable<string> orderedCandidateIds)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(pluginId);
        ArgumentException.ThrowIfNullOrWhiteSpace(reasonCode);
        pluginVersion.EnsureInitialized(nameof(pluginVersion));
        var ids = (orderedCandidateIds ?? throw new ArgumentNullException(nameof(orderedCandidateIds))).ToArray();
        PluginId = pluginId;
        PluginVersion = pluginVersion;
        Outcome = outcome;
        ReasonCode = reasonCode;
        OrderedCandidateIds = Array.AsReadOnly(ids);
    }

    public int SchemaVersion => 1;
    public string PluginId { get; }
    public ContractVersion PluginVersion { get; }
    public RouterPluginOutcome Outcome { get; }
    public string ReasonCode { get; }
    public IReadOnlyList<string> OrderedCandidateIds { get; }
}

public sealed record RouterPluginTrace(
    string PluginId,
    ContractVersion PluginVersion,
    RouterPluginOutcome Outcome,
    string ReasonCode);

public enum RouteOutcome
{
    Selected,
    NoRoute,
    Indeterminate
}

public sealed record RouteDecision(
    string RequestId,
    string TraceId,
    string TenantId,
    long ConfigVersion,
    string ModelAlias,
    string RouteStrategy,
    RouteOutcome Outcome,
    string ReasonCode,
    string? SelectedProviderId,
    IReadOnlyList<string> OrderedCandidateIds,
    IReadOnlyList<RouterPluginTrace> PluginTrace,
    IReadOnlyList<string> AppliedObligationKinds,
    IReadOnlyList<PolicyObligation> ForwardedObligations)
{
    public int SchemaVersion => 1;
}

public sealed record RouterPluginRegistration
{
    public RouterPluginRegistration(string pluginId, ContractVersion pluginVersion, bool enabled)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(pluginId);
        pluginVersion.EnsureInitialized(nameof(pluginVersion));
        PluginId = pluginId;
        PluginVersion = pluginVersion;
        Enabled = enabled;
    }

    public string PluginId { get; }
    public ContractVersion PluginVersion { get; }
    public bool Enabled { get; }
}

public sealed record RouterPipelineRegistration(string RouteStrategy, IReadOnlyList<string> PluginIds)
{
    public RouterPipelineRegistration(string routeStrategy, IEnumerable<string> pluginIds)
        : this(
            string.IsNullOrWhiteSpace(routeStrategy)
                ? throw new ArgumentException("Route strategy is required.", nameof(routeStrategy))
                : routeStrategy,
            Array.AsReadOnly((pluginIds ?? throw new ArgumentNullException(nameof(pluginIds))).ToArray()))
    {
        if (PluginIds.Count == 0 ||
            PluginIds.Any(string.IsNullOrWhiteSpace) ||
            PluginIds.Distinct(StringComparer.Ordinal).Count() != PluginIds.Count)
        {
            throw new ArgumentException("Plugin IDs must be non-empty and unique.", nameof(pluginIds));
        }
    }
}

public sealed record RouterRegistry(
    string TenantId,
    long ConfigVersion,
    IReadOnlyList<RouterPluginRegistration> Plugins,
    IReadOnlyList<RouterPipelineRegistration> Pipelines)
{
    public RouterRegistry(
        string tenantId,
        long configVersion,
        IEnumerable<RouterPluginRegistration> plugins,
        IEnumerable<RouterPipelineRegistration> pipelines)
        : this(
            string.IsNullOrWhiteSpace(tenantId)
                ? throw new ArgumentException("Tenant ID is required.", nameof(tenantId))
                : tenantId,
            configVersion < 1
                ? throw new ArgumentOutOfRangeException(nameof(configVersion))
                : configVersion,
            Array.AsReadOnly((plugins ?? throw new ArgumentNullException(nameof(plugins))).ToArray()),
            Array.AsReadOnly((pipelines ?? throw new ArgumentNullException(nameof(pipelines))).ToArray()))
    {
    }

    public int SchemaVersion => 1;
}
