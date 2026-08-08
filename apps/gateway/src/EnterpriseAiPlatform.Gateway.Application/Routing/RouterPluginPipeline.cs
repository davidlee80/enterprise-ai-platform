using EnterpriseAiPlatform.Gateway.Domain.Policy;
using EnterpriseAiPlatform.Gateway.Domain.Routing;

namespace EnterpriseAiPlatform.Gateway.Application.Routing;

public sealed class RouterPluginPipeline
{
    private readonly IReadOnlyDictionary<string, IRouterPlugin> _plugins;

    public RouterPluginPipeline(IEnumerable<IRouterPlugin> plugins)
    {
        ArgumentNullException.ThrowIfNull(plugins);
        var pluginArray = plugins.ToArray();
        if (pluginArray.Any(plugin => string.IsNullOrWhiteSpace(plugin.PluginId)) ||
            pluginArray.GroupBy(plugin => plugin.PluginId, StringComparer.Ordinal).Any(group => group.Count() != 1))
        {
            throw new ArgumentException("Router plugin IDs must be non-empty and unique.", nameof(plugins));
        }

        _plugins = pluginArray.ToDictionary(plugin => plugin.PluginId, StringComparer.Ordinal);
    }

    public async ValueTask<RouteDecision> RouteAsync(
        RouterRequest request,
        RouterRegistry registry,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(registry);
        cancellationToken.ThrowIfCancellationRequested();

        var trace = new List<RouterPluginTrace>();
        var forwardedObligations = request.Obligations
            .Where(obligation => !string.Equals(obligation.Kind, "force_region", StringComparison.Ordinal))
            .ToArray();

        if (request.PolicyOutcome != PolicyOutcome.Allow)
        {
            return Decision(RouteOutcome.NoRoute, "POLICY_NOT_ALLOWED", null, [], trace, [], forwardedObligations);
        }

        if (!string.Equals(request.TenantId, registry.TenantId, StringComparison.Ordinal))
        {
            return Decision(RouteOutcome.Indeterminate, "ROUTER_TENANT_MISMATCH", null, [], trace, [], forwardedObligations);
        }

        if (request.ConfigVersion != registry.ConfigVersion)
        {
            return Decision(RouteOutcome.Indeterminate, "ROUTER_CONFIG_VERSION_MISMATCH", null, [], trace, [], forwardedObligations);
        }

        if (request.Candidates.GroupBy(candidate => candidate.ProviderId, StringComparer.Ordinal).Any(group => group.Count() != 1))
        {
            return Decision(RouteOutcome.Indeterminate, "ROUTER_CANDIDATE_SET_INVALID", null, [], trace, [], forwardedObligations);
        }

        var eligible = request.Candidates.Where(candidate => candidate.Enabled).ToList();
        var forceRegions = request.Obligations
            .Where(obligation => string.Equals(obligation.Kind, "force_region", StringComparison.Ordinal))
            .Select(obligation => obligation.Region!)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        if (forceRegions.Length > 1)
        {
            return Decision(RouteOutcome.Indeterminate, "ROUTER_OBLIGATION_CONFLICT", null, [], trace, [], forwardedObligations);
        }

        var appliedObligationKinds = Array.Empty<string>();
        if (forceRegions.Length == 1)
        {
            eligible = eligible
                .Where(candidate => string.Equals(candidate.Region, forceRegions[0], StringComparison.Ordinal))
                .ToList();
            appliedObligationKinds = ["force_region"];
        }

        if (eligible.Count == 0)
        {
            return Decision(RouteOutcome.NoRoute, "NO_ELIGIBLE_CANDIDATE", null, [], trace, appliedObligationKinds, forwardedObligations);
        }

        var pipelines = registry.Pipelines
            .Where(pipeline => string.Equals(pipeline.RouteStrategy, request.RouteStrategy, StringComparison.Ordinal))
            .ToArray();
        if (pipelines.Length == 0)
        {
            return Decision(RouteOutcome.NoRoute, "ROUTE_STRATEGY_NOT_REGISTERED", null, [], trace, appliedObligationKinds, forwardedObligations);
        }

        if (pipelines.Length != 1 ||
            registry.Plugins.GroupBy(plugin => plugin.PluginId, StringComparer.Ordinal).Any(group => group.Count() != 1))
        {
            return Decision(RouteOutcome.Indeterminate, "ROUTER_REGISTRY_INVALID", null, [], trace, appliedObligationKinds, forwardedObligations);
        }

        var registrations = registry.Plugins.ToDictionary(plugin => plugin.PluginId, StringComparer.Ordinal);
        var orderedCandidates = eligible.ToArray();
        foreach (var pluginId in pipelines[0].PluginIds)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!registrations.TryGetValue(pluginId, out var registration) ||
                !registration.Enabled ||
                !_plugins.TryGetValue(pluginId, out var plugin) ||
                plugin.PluginVersion != registration.PluginVersion)
            {
                return Decision(
                    RouteOutcome.Indeterminate,
                    "ROUTER_PLUGIN_UNAVAILABLE",
                    null,
                    orderedCandidates.Select(candidate => candidate.ProviderId).ToArray(),
                    trace,
                    appliedObligationKinds,
                    forwardedObligations);
            }

            RouterPluginResult result;
            try
            {
                result = await plugin.RouteAsync(
                    new RouterPluginContext(request, orderedCandidates),
                    cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception)
            {
                return Decision(
                    RouteOutcome.Indeterminate,
                    "ROUTER_PLUGIN_UNAVAILABLE",
                    null,
                    orderedCandidates.Select(candidate => candidate.ProviderId).ToArray(),
                    trace,
                    appliedObligationKinds,
                    forwardedObligations);
            }

            if (result is null)
            {
                return Decision(
                    RouteOutcome.Indeterminate,
                    "ROUTER_PLUGIN_RESULT_INVALID",
                    null,
                    orderedCandidates.Select(candidate => candidate.ProviderId).ToArray(),
                    trace,
                    appliedObligationKinds,
                    forwardedObligations);
            }

            trace.Add(new RouterPluginTrace(
                result.PluginId,
                result.PluginVersion,
                result.Outcome,
                result.ReasonCode));

            if (!IsValid(result, registration, orderedCandidates))
            {
                return Decision(
                    RouteOutcome.Indeterminate,
                    "ROUTER_PLUGIN_RESULT_INVALID",
                    null,
                    orderedCandidates.Select(candidate => candidate.ProviderId).ToArray(),
                    trace,
                    appliedObligationKinds,
                    forwardedObligations);
            }

            if (result.Outcome == RouterPluginOutcome.Rejected)
            {
                return Decision(RouteOutcome.NoRoute, result.ReasonCode, null, [], trace, appliedObligationKinds, forwardedObligations);
            }

            if (result.Outcome == RouterPluginOutcome.Indeterminate)
            {
                return Decision(
                    RouteOutcome.Indeterminate,
                    result.ReasonCode,
                    null,
                    orderedCandidates.Select(candidate => candidate.ProviderId).ToArray(),
                    trace,
                    appliedObligationKinds,
                    forwardedObligations);
            }

            if (result.Outcome == RouterPluginOutcome.Applied)
            {
                var byId = orderedCandidates.ToDictionary(candidate => candidate.ProviderId, StringComparer.Ordinal);
                orderedCandidates = result.OrderedCandidateIds.Select(id => byId[id]).ToArray();
            }

            if (orderedCandidates.Length == 0)
            {
                return Decision(RouteOutcome.NoRoute, "NO_ELIGIBLE_CANDIDATE", null, [], trace, appliedObligationKinds, forwardedObligations);
            }
        }

        var ids = orderedCandidates.Select(candidate => candidate.ProviderId).ToArray();
        return Decision(RouteOutcome.Selected, "ROUTE_SELECTED", ids[0], ids, trace, appliedObligationKinds, forwardedObligations);

        RouteDecision Decision(
            RouteOutcome outcome,
            string reasonCode,
            string? selectedProviderId,
            IReadOnlyList<string> orderedCandidateIds,
            IReadOnlyList<RouterPluginTrace> pluginTrace,
            IReadOnlyList<string> appliedKinds,
            IReadOnlyList<PolicyObligation> forwarded) =>
            new(
                request.RequestId,
                request.TraceId,
                request.TenantId,
                request.ConfigVersion,
                request.ModelAlias,
                request.RouteStrategy,
                outcome,
                reasonCode,
                selectedProviderId,
                orderedCandidateIds,
                pluginTrace.ToArray(),
                appliedKinds.ToArray(),
                forwarded.ToArray());
    }

    private static bool IsValid(
        RouterPluginResult result,
        RouterPluginRegistration registration,
        IReadOnlyList<RouterCandidate> currentCandidates)
    {
        if (!string.Equals(result.PluginId, registration.PluginId, StringComparison.Ordinal) ||
            result.PluginVersion != registration.PluginVersion ||
            string.IsNullOrWhiteSpace(result.ReasonCode) ||
            !char.IsAsciiLetterUpper(result.ReasonCode[0]) ||
            result.ReasonCode.Any(character => character != '_' && !char.IsAsciiLetterUpper(character) && !char.IsAsciiDigit(character)))
        {
            return false;
        }

        var ids = result.OrderedCandidateIds;
        var currentIds = currentCandidates.Select(candidate => candidate.ProviderId).ToHashSet(StringComparer.Ordinal);
        return ids.Distinct(StringComparer.Ordinal).Count() == ids.Count &&
               ids.All(currentIds.Contains);
    }
}
